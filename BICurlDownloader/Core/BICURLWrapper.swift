//
//  BICURLWrapper.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import Curl

/// Тип запроса для BICURLWrapper
enum BICURLRequestType {
    case download(outputPath: String, range: String?)  // Загрузка файла с опциональным диапазоном
    case head                                           // HEAD запрос для получения метаданных
}

/// Результат выполнения запроса
struct BICURLRequestResult {
    let httpResponseCode: Int32
    let headers: [String: String]
    let effectiveURL: String?
    let redirectCount: Int
    let bytesDownloaded: Int64
    let totalBytesExpected: Int64
    
    var supportsRangeRequests: Bool {
        if let acceptRanges = headers["accept-ranges"]?.lowercased() {
            if acceptRanges == "none" { return false }
            if acceptRanges == "bytes" { return true }
        }
        
        if httpResponseCode == 206 { return true }
        if headers["content-range"] != nil { return true }
        
        return false
    }
    
    var contentLength: Int64? {
        // Сначала проверяем Content-Range, т.к. он содержит полный размер файла
        if let contentRange = headers["content-range"] {
            // Формат: "bytes 0-0/12345" или "bytes 100-200/12345"
            let components = contentRange.components(separatedBy: "/")
            if components.count == 2, let totalSize = Int64(components[1]) {
                return totalSize
            }
        }
        
        // Если Content-Range нет, используем Content-Length
        if let lengthStr = headers["content-length"], let length = Int64(lengthStr) {
            return length
        }
        
        return nil
    }
    
    var etag: String? {
        return headers["etag"]
    }
    
    var lastModified: String? {
        return headers["last-modified"]
    }
}

/// Delegate protocol for BICURLWrapper
protocol BICURLWrapperDelegate: AnyObject {
    func curlWrapperDidUpdateProgress(_ wrapper: BICURLWrapper, bytesDownloaded: Int64, totalBytes: Int64)
    func curlWrapperDidComplete(_ wrapper: BICURLWrapper, result: BICURLRequestResult)
    func curlWrapperDidFail(_ wrapper: BICURLWrapper, error: Error)
}

/// Единственный класс для работы с cURL
class BICURLWrapper: NSObject {
    
    // MARK: - Properties
    
    let url: URL
    let options: BIDownloadOptions
    let requestType: BICURLRequestType
    let identifier: String
    
    weak var delegate: BICURLWrapperDelegate?
    
    internal var curlHandle: OpaquePointer?
    internal var outputFileHandle: FileHandle?
    internal var headersList: UnsafeMutablePointer<curl_slist>?
    
    internal var isPaused = false
    internal var isCancelled = false
    internal var bytesDownloaded: Int64 = 0
    private var totalBytesExpected: Int64 = 0
    
    internal var redirectChain: [(url: String, code: Int)] = []
    internal var finalURL: String?
    internal var responseHeaders: [String: String] = [:]
    
    internal let logger = BILogger.shared
    internal let fileManager = BIFileManager.shared
    internal var lastProgressTime = Date()
    
    // MARK: - Initialization
    
    init(url: URL, options: BIDownloadOptions, requestType: BICURLRequestType, identifier: String = UUID().uuidString) {
        self.url = url
        self.options = options
        self.requestType = requestType
        self.identifier = identifier
        super.init()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Methods
    
    func start() {
        let typeDescription: String
        switch requestType {
        case .download(let path, let range):
            if let range = range {
                typeDescription = "download with range \(range) to \(path)"
            } else {
                typeDescription = "download full file to \(path)"
            }
        case .head:
            typeDescription = "HEAD request"
        }
        logger.info("[\(identifier)] Starting \(typeDescription) for URL: \(url)")
        
        guard !isCancelled else {
            logger.warning("[\(identifier)] Cannot start cancelled request")
            return
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performRequest()
        }
    }
    
    func pause() {
        logger.info("[\(identifier)] Pausing request")
        isPaused = true
    }
    
    func resume() {
        logger.info("[\(identifier)] Resuming request")
        isPaused = false
    }
    
    func cancel() {
        logger.info("[\(identifier)] Cancelling request")
        isCancelled = true
        cleanup()
    }
    
    // MARK: - Private Methods
    
    private func performRequest() {
        guard setupCURL() else {
            let error = BIDownloadError.curlError(code: -1, message: "Failed to setup cURL")
            notifyError(error)
            return
        }
        
        defer { cleanup() }
        
        guard let handle = curlHandle else {
            let error = BIDownloadError.curlError(code: -1, message: "cURL handle is nil")
            notifyError(error)
            return
        }
        
        let curlPtr = UnsafeMutableRawPointer(handle)
        let result = curl_easy_perform(curlPtr)
        
        if result == CURLE_OK && !isCancelled {
            handleSuccessfulRequest(curlPtr: curlPtr)
        } else if result != CURLE_OK && !isCancelled {
            handleFailedRequest(curlPtr: curlPtr, curlResult: result)
        }
    }
    
    private func handleSuccessfulRequest(curlPtr: UnsafeMutableRawPointer) {
        var responseCode: Int32 = 0
        _ = curl_easy_getinfo_int(curlPtr, CURLINFO_RESPONSE_CODE, &responseCode)
        
        var effectiveURL: UnsafePointer<Int8>? = nil
        let infoResult = curl_easy_getinfo_string(curlPtr, CURLINFO_EFFECTIVE_URL, &effectiveURL)
        var effectiveURLString: String? = nil
        if infoResult == CURLE_OK, let urlPtr = effectiveURL {
            effectiveURLString = String(cString: urlPtr)
            if effectiveURLString != url.absoluteString {
                logger.info("[\(identifier)] Effective URL after redirects: \(effectiveURLString ?? "")")
                finalURL = effectiveURLString
            }
        }
        
        if !redirectChain.isEmpty {
            logger.info("[\(identifier)] Redirect chain: \(redirectChain.count) redirect(s)")
        }
        
        // Логируем полученные заголовки
        logResponseDetails(responseCode: responseCode, effectiveURL: effectiveURLString)
        
        if responseCode >= 200 && responseCode < 400 {
            if case .download(let outputPath, _) = requestType {
                if let fileHandle = outputFileHandle {
                    fileHandle.closeFile()
                    outputFileHandle = nil
                    
                    if !validateDownloadedContent(at: outputPath) {
                        let error = BIDownloadError.serverError(code: Int(responseCode), message: "Server returned error page instead of content")
                        notifyError(error)
                        return
                    }
                }
            }
            
            logger.info("[\(identifier)] Request completed successfully, HTTP \(responseCode), downloaded: \(bytesDownloaded) bytes")
            notifyCompletion(responseCode: responseCode, effectiveURL: effectiveURLString)
        } else {
            let error = BIDownloadError.serverError(code: Int(responseCode), message: "HTTP error \(responseCode)")
            logger.error("[\(identifier)] HTTP error \(responseCode)")
            notifyError(error)
        }
    }
    
    private func handleFailedRequest(curlPtr: UnsafeMutableRawPointer, curlResult: CURLcode) {
        let errorMessage = String(cString: curl_easy_strerror(curlResult))
        
        var responseCode: Int32 = 0
        _ = curl_easy_getinfo_int(curlPtr, CURLINFO_RESPONSE_CODE, &responseCode)
        
        let error: Error
        if responseCode == 416 {
            error = BIDownloadError.serverError(code: 416, message: "Range Not Satisfiable")
        } else {
            error = BIDownloadError.curlError(code: Int(curlResult.rawValue), message: "\(errorMessage) (HTTP \(responseCode))")
        }
        
        logger.error("[\(identifier)] cURL request failed: \(errorMessage), HTTP: \(responseCode)")
        notifyError(error)
    }
    
    private func cleanup() {
        outputFileHandle?.closeFile()
        outputFileHandle = nil
        
        if let headersList = headersList {
            curl_slist_free_all(headersList)
            self.headersList = nil
        }
        
        if let handle = curlHandle {
            curl_easy_cleanup(UnsafeMutableRawPointer(handle))
            curlHandle = nil
        }
    }
    
    private func validateDownloadedContent(at path: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let content = String(data: data.prefix(500), encoding: .utf8) {
                let lowerContent = content.lowercased()
                if lowerContent.contains("<html") ||
                   lowerContent.contains("range not satisfiable") ||
                   lowerContent.contains("nginx") ||
                   lowerContent.contains("<!doctype") {
                    logger.error("[\(identifier)] Server returned HTML error page")
                    return false
                }
            }
            return true
        } catch {
            logger.error("[\(identifier)] Failed to verify download content: \(error)")
            return false
        }
    }
    
    private func notifyCompletion(responseCode: Int32, effectiveURL: String?) {
        logger.info("[\(identifier)] Creating result object...")
        
        let result = BICURLRequestResult(
            httpResponseCode: responseCode,
            headers: responseHeaders,
            effectiveURL: effectiveURL,
            redirectCount: redirectChain.count,
            bytesDownloaded: bytesDownloaded,
            totalBytesExpected: totalBytesExpected
        )
        
        logger.info("[\(identifier)] Result created, headers count: \(responseHeaders.count)")
        logger.info("[\(identifier)] Checking delegate: \(delegate != nil ? "exists" : "nil")")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                BILogger.shared.warning("[?] Self is nil in notifyCompletion")
                return
            }
            
            self.logger.info("[\(self.identifier)] Calling delegate.curlWrapperDidComplete")
            self.delegate?.curlWrapperDidComplete(self, result: result)
            self.logger.info("[\(self.identifier)] Delegate call completed")
        }
    }
    
    private func notifyError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.curlWrapperDidFail(self, error: error)
        }
    }
    
    internal func notifyProgress() {
        let total = max(totalBytesExpected, bytesDownloaded)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.curlWrapperDidUpdateProgress(self, bytesDownloaded: self.bytesDownloaded, totalBytes: total)
        }
    }
    
    internal func logCurlDebugInfo(type: Int32, info: String) {
        let prefix: String
        switch type {
        case 0: prefix = "[CURL INFO]"
        case 1: prefix = "[CURL HEADER IN]"
        case 2: prefix = "[CURL HEADER OUT]"
        default: prefix = "[CURL DEBUG]"
        }
        
        if type == 2 {
            logger.info("[\(identifier)] \(prefix)\n\(info)")
        } else if type == 0 || type == 1 {
            logger.debug("[\(identifier)] \(prefix) \(info)")
        }
    }
    
    internal func logResponseDetails(responseCode: Int32, effectiveURL: String?) {
        logger.info("[────────────────────────────────────────]")
        logger.info("[\(identifier)] 📥 INCOMING RESPONSE DETAILS")
        logger.info("[────────────────────────────────────────]")
        
        logger.info("[\(identifier)] Status: HTTP \(responseCode)")
        
        if let effectiveURL = effectiveURL, effectiveURL != url.absoluteString {
            logger.info("[\(identifier)] Final URL: \(effectiveURL)")
        }
        
        if !redirectChain.isEmpty {
            logger.info("[\(identifier)] Redirects: \(redirectChain.count)")
            for (index, redirect) in redirectChain.enumerated() {
                logger.info("[\(identifier)]   \(index + 1). HTTP \(redirect.code) → \(redirect.url)")
            }
        }
        
        if !responseHeaders.isEmpty {
            logger.info("[\(identifier)] Response Headers:")
            
            // Важные заголовки сначала
            let importantHeaders = [
                "content-length",
                "content-type",
                "content-range",
                "accept-ranges",
                "etag",
                "last-modified",
                "server",
                "date"
            ]
            
            for key in importantHeaders {
                if let value = responseHeaders[key] {
                    logger.info("[\(identifier)]   \(key): \(value)")
                }
            }
            
            // Остальные заголовки
            let otherHeaders = responseHeaders.filter { !importantHeaders.contains($0.key) }
            if !otherHeaders.isEmpty {
                logger.debug("[\(identifier)] Other Headers:")
                for (key, value) in otherHeaders.sorted(by: { $0.key < $1.key }) {
                    logger.debug("[\(identifier)]   \(key): \(value)")
                }
            }
        }
        
        logger.info("[────────────────────────────────────────]")
    }
}
