//
//  BIServerCapabilities.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

/// Информация о возможностях сервера
struct BIServerCapabilitiesInfo {
    let supportsRangeRequests: Bool
    let contentLength: Int64?
    let lastModified: String?
    let etag: String?
    let acceptRanges: String?
    let httpResponseCode: Int32
    let effectiveURL: String?
    
    init(supportsRangeRequests: Bool = false, 
         contentLength: Int64? = nil, 
         lastModified: String? = nil,
         etag: String? = nil,
         acceptRanges: String? = nil, 
         httpResponseCode: Int32 = 0, 
         effectiveURL: String? = nil) {
        self.supportsRangeRequests = supportsRangeRequests
        self.contentLength = contentLength
        self.lastModified = lastModified
        self.etag = etag
        self.acceptRanges = acceptRanges
        self.httpResponseCode = httpResponseCode
        self.effectiveURL = effectiveURL
    }
}

/// Класс для проверки возможностей сервера (через BICURLWrapper)
class BIServerCapabilities {
    
    private let logger = BILogger.shared
    private var currentWrapper: BICURLWrapper?
    private var completionCallback: ((Result<BIServerCapabilitiesInfo, Error>) -> Void)?
    
    /// Проверка возможностей сервера
    func check(
        url: URL,
        options: BIDownloadOptions,
        completion: @escaping (Result<BIServerCapabilitiesInfo, Error>) -> Void
    ) {
        logger.info("[ServerCap] Starting capabilities check for: \(url)")
        
        // Сохраняем completion
        self.completionCallback = completion
        
        // Выполняем HEAD запрос через BICURLWrapper
        let wrapper = BICURLWrapper(
            url: url,
            options: options,
            requestType: .head,
            identifier: "ServerCap-\(UUID().uuidString.prefix(8))"
        )
        
        currentWrapper = wrapper
        wrapper.delegate = self
        
        wrapper.start()
    }
}

// MARK: - BICURLWrapperDelegate

extension BIServerCapabilities: BICURLWrapperDelegate {
    
    func curlWrapperDidUpdateProgress(_ wrapper: BICURLWrapper, bytesDownloaded: Int64, totalBytes: Int64) {
        // Не нужно для проверки возможностей
    }
    
    func curlWrapperDidComplete(_ wrapper: BICURLWrapper, result: BICURLRequestResult) {
        logger.info("[ServerCap] curlWrapperDidComplete called")
        
        guard let completion = completionCallback else {
            logger.error("[ServerCap] Completion callback is nil")
            return
        }
        
        logger.info("[ServerCap] HEAD request completed, HTTP \(result.httpResponseCode)")
        logger.debug("[ServerCap] Headers: \(result.headers)")
        
        let info = BIServerCapabilitiesInfo(
            supportsRangeRequests: result.supportsRangeRequests,
            contentLength: result.contentLength,
            lastModified: result.lastModified,
            etag: result.etag,
            acceptRanges: result.headers["accept-ranges"],
            httpResponseCode: result.httpResponseCode,
            effectiveURL: result.effectiveURL
        )
        
        if result.supportsRangeRequests {
            logger.info("[ServerCap] ✓ Server supports Range requests")
        } else {
            logger.info("[ServerCap] ✗ Server does not support Range requests")
        }
        
        if let contentLength = info.contentLength {
            logger.info("[ServerCap] Content-Length: \(contentLength) bytes")
        } else {
            logger.warning("[ServerCap] Content-Length not available")
        }
        
        DispatchQueue.main.async { [weak self] in
            completion(.success(info))
            self?.completionCallback = nil
        }
        
        currentWrapper = nil
    }
    
    func curlWrapperDidFail(_ wrapper: BICURLWrapper, error: Error) {
        guard let completion = completionCallback else {
            logger.error("[ServerCap] Completion callback is nil in didFail")
            return
        }
        
        logger.error("[ServerCap] HEAD request failed: \(error.localizedDescription)")
        
        // Возвращаем базовую информацию вместо ошибки
        let basicInfo = BIServerCapabilitiesInfo(
            supportsRangeRequests: false,
            contentLength: nil,
            lastModified: nil,
            etag: nil,
            acceptRanges: nil,
            httpResponseCode: 0,
            effectiveURL: nil
        )
        
        logger.warning("[ServerCap] Using basic capabilities (no Range support)")
        
        DispatchQueue.main.async { [weak self] in
            completion(.success(basicInfo))
            self?.completionCallback = nil
        }
        
        currentWrapper = nil
    }
}
