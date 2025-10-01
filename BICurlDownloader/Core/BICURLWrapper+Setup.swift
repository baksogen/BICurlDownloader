//
//  BICURLWrapper+Setup.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import Curl

// MARK: - cURL Setup Extension

extension BICURLWrapper {
    
    func setupCURL() -> Bool {
        guard let curlHandleRaw = curl_easy_init() else {
            return false
        }
        
        curlHandle = OpaquePointer(curlHandleRaw)
        guard let handle = curlHandle else {
            return false
        }
        
        let curlPtr = UnsafeMutableRawPointer(handle)
        
        // Базовые настройки
        _ = curl_easy_setopt_string(curlPtr, CURLOPT_URL, url.absoluteString)
        
        // Debug mode
        setupDebugMode(curlPtr: curlPtr)
        
        // Настройка в зависимости от типа запроса
        switch requestType {
        case .download(let outputPath, let range):
            if !setupDownloadRequest(curlPtr: curlPtr, outputPath: outputPath, range: range) {
                return false
            }
        case .head:
            setupHeadRequest(curlPtr: curlPtr)
        }
        
        // Общие настройки
        setupTimeouts(curlPtr: curlPtr)
        setupRedirects(curlPtr: curlPtr)
        setupHeaderCallback(curlPtr: curlPtr)
        setupSSLConfiguration(curlPtr: curlPtr)
        
        // User Agent
        _ = curl_easy_setopt_string(curlPtr, CURLOPT_USERAGENT, options.userAgent)
        
        // Custom headers and auth
        setupCustomHeaders()
        setupAuthentication(curlPtr: curlPtr)
        
        // Установка заголовков
        if headersList != nil {
            _ = curl_easy_setopt_slist(curlPtr, CURLOPT_HTTPHEADER, headersList)
        }
        
        // Логируем все параметры запроса перед отправкой
        logRequestDetails(curlPtr: curlPtr)
        
        return true
    }
    
    private func setupDebugMode(curlPtr: UnsafeMutableRawPointer) {
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_VERBOSE, 1)
        _ = curl_easy_setopt_debug_function(curlPtr, CURLOPT_DEBUGFUNCTION) { (handle, type, data, size, userdata) -> Int32 in
            guard let userdata = userdata else { return 0 }
            let wrapper = Unmanaged<BICURLWrapper>.fromOpaque(userdata).takeUnretainedValue()
            
            if let data = data {
                let debugData = Data(bytes: data, count: size)
                if let debugString = String(data: debugData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    wrapper.logCurlDebugInfo(type: Int32(type.rawValue), info: debugString)
                }
            }
            
            return 0
        }
        _ = curl_easy_setopt_pointer(curlPtr, CURLOPT_DEBUGDATA, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func setupTimeouts(curlPtr: UnsafeMutableRawPointer) {
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_CONNECTTIMEOUT, 30)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_LOW_SPEED_LIMIT, 1024)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_LOW_SPEED_TIME, Int32(options.timeoutInterval))
        
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_FAILONERROR, 0)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_NOSIGNAL, 1)
    }
    
    private func setupRedirects(curlPtr: UnsafeMutableRawPointer) {
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_FOLLOWLOCATION, 1)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_MAXREDIRS, 15)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_UNRESTRICTED_AUTH, 0)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_POSTREDIR, 7)
    }
    
    func setupDownloadRequest(curlPtr: UnsafeMutableRawPointer, outputPath: String, range: String?) -> Bool {
        // Установка Range заголовка если указан
        if let range = range {
            logger.debug("[\(identifier)] Setting Range: bytes=\(range)")
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_RANGE, range)
        }
        
        // Write callback для данных
        let callback: curl_write_callback = { (buffer, size, nitems, userdata) -> Int in
            guard let userdata = userdata else { return 0 }
            let wrapper = Unmanaged<BICURLWrapper>.fromOpaque(userdata).takeUnretainedValue()
            
            if wrapper.isPaused {
                return Int(CURL_WRITEFUNC_PAUSE)
            }
            
            if wrapper.isCancelled {
                return 0
            }
            
            guard let buffer = buffer else {
                wrapper.logger.error("[\(wrapper.identifier)] Write callback received nil buffer")
                return 0
            }
            
            let dataSize = size * nitems
            guard dataSize > 0 else { return 0 }
            
            let data = Data(bytes: buffer, count: dataSize)
            
            // Проверка первых байтов на HTML/ошибки
            if wrapper.bytesDownloaded == 0 && dataSize > 0 {
                if let content = String(data: data.prefix(min(500, dataSize)), encoding: .utf8) {
                    let lowerContent = content.lowercased()
                    if lowerContent.contains("<html") ||
                       lowerContent.contains("<!doctype html") ||
                       lowerContent.contains("<title>") ||
                       lowerContent.contains("range not satisfiable") ||
                       lowerContent.contains("404 not found") ||
                       lowerContent.contains("403 forbidden") {
                        wrapper.logger.error("[\(wrapper.identifier)] Detected HTML/error page response")
                        return 0
                    }
                }
            }
            
            guard let fileHandle = wrapper.outputFileHandle else {
                wrapper.logger.error("[\(wrapper.identifier)] Output file handle is nil")
                return 0
            }
            
            fileHandle.write(data)
            wrapper.bytesDownloaded += Int64(dataSize)
            
            let now = Date()
            if now.timeIntervalSince(wrapper.lastProgressTime) >= 0.1 {
                wrapper.lastProgressTime = now
                wrapper.notifyProgress()
            }
            
            return dataSize
        }
        
        _ = curl_easy_setopt_write_function(curlPtr, CURLOPT_WRITEFUNCTION, callback)
        _ = curl_easy_setopt_pointer(curlPtr, CURLOPT_WRITEDATA, Unmanaged.passUnretained(self).toOpaque())
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_NOPROGRESS, 1)
        
        // Создание выходного файла
        return createOutputFile(path: outputPath)
    }
    
    func setupHeadRequest(curlPtr: UnsafeMutableRawPointer) {
        // Используем GET с Range: bytes=0-0 для надежности
        _ = curl_easy_setopt_string(curlPtr, CURLOPT_RANGE, "0-0")
        
        // Write callback для игнорирования тела ответа
        _ = curl_easy_setopt_write_function(curlPtr, CURLOPT_WRITEFUNCTION, { (buffer, size, nitems, userdata) -> Int in
            return size * nitems
        })
    }
    
    private func createOutputFile(path: String) -> Bool {
        let directoryCheck = fileManager.checkDirectoryAccess(at: path)
        if !directoryCheck.writable {
            if let error = directoryCheck.error {
                logger.error("[\(identifier)] Directory access check failed: \(error)")
            }
            return false
        }
        
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let testResult = fileManager.testFileCreation(in: directory)
        if !testResult.success {
            if let error = testResult.error {
                logger.error("[\(identifier)] File creation test failed: \(error)")
            }
            return false
        }
        
        do {
            let directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                logger.debug("[\(identifier)] Removed existing file: \(path)")
            }
            
            let success = FileManager.default.createFile(atPath: path, contents: Data(), attributes: [
                .posixPermissions: 0o644
            ])
            
            guard success else {
                logger.error("[\(identifier)] Failed to create file: \(path)")
                return false
            }
            
            guard FileManager.default.fileExists(atPath: path) else {
                logger.error("[\(identifier)] File was not created: \(path)")
                return false
            }
            
            outputFileHandle = FileHandle(forWritingAtPath: path)
            
            if outputFileHandle == nil {
                logger.error("[\(identifier)] Failed to open file for writing: \(path)")
                try? FileManager.default.removeItem(atPath: path)
                return false
            }
            
            logger.debug("[\(identifier)] Successfully created output file: \(path)")
            return true
            
        } catch {
            logger.error("[\(identifier)] Error creating output file: \(error)")
            return false
        }
    }
    
    // MARK: - Request Logging
    
    private func logRequestDetails(curlPtr: UnsafeMutableRawPointer) {
        logger.info("[────────────────────────────────────────]")
        logger.info("[\(identifier)] 🚀 OUTGOING REQUEST DETAILS")
        logger.info("[────────────────────────────────────────]")
        
        // URL and method
        let method: String
        switch requestType {
        case .head:
            method = "GET (with Range: bytes=0-0)"
        case .download(_, let range):
            if range != nil {
                method = "GET (with Range)"
            } else {
                method = "GET"
            }
        }
        
        logger.info("[\(identifier)] Method: \(method)")
        logger.info("[\(identifier)] URL: \(url.absoluteString)")
        
        // Request type
        switch requestType {
        case .head:
            logger.info("[\(identifier)] Type: HEAD request (server capabilities check)")
            logger.info("[\(identifier)] Range: bytes=0-0 (minimal data request)")
            
        case .download(let path, let range):
            if let range = range {
                logger.info("[\(identifier)] Type: Partial download (multipart)")
                logger.info("[\(identifier)] Range: bytes=\(range)")
            } else {
                logger.info("[\(identifier)] Type: Full file download")
            }
            logger.info("[\(identifier)] Output: \(path)")
        }
        
        // Headers
        logger.info("[\(identifier)] Headers:")
        logger.info("[\(identifier)]   User-Agent: \(options.userAgent)")
        logger.info("[\(identifier)]   Accept: */*")
        
        // Custom headers
        if !options.customHeaders.isEmpty {
            logger.info("[\(identifier)] Custom Headers:")
            for (key, value) in options.customHeaders {
                logger.info("[\(identifier)]   \(key): \(value)")
            }
        }
        
        // Authentication
        if let auth = options.authentication {
            switch auth.type {
            case .basic(let username, _):
                logger.info("[\(identifier)] Authentication: Basic (user: \(username))")
            case .digest(let username, _):
                logger.info("[\(identifier)] Authentication: Digest (user: \(username))")
            case .bearer:
                logger.info("[\(identifier)] Authentication: Bearer Token")
            case .custom(let header, _):
                logger.info("[\(identifier)] Authentication: Custom (header: \(header))")
            }
        }
        
        // Additional cURL options
        logger.info("[\(identifier)] Connection Settings:")
        logger.info("[\(identifier)]   Connect Timeout: 30s")
        logger.info("[\(identifier)]   Low Speed Limit: 1024 bytes/s")
        logger.info("[\(identifier)]   Low Speed Time: \(options.timeoutInterval)s")
        logger.info("[\(identifier)]   Follow Redirects: Yes (max 15)")
        logger.info("[\(identifier)]   SSL Verification: \(options.sslVerification ? "Enabled" : "Disabled")")
        
        if !options.allowsCellularAccess {
            logger.info("[\(identifier)]   Cellular: Disabled")
        }
        
        logger.info("[────────────────────────────────────────]")
    }
}
