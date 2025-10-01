//
//  BICURLWrapper+Headers.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import Curl

// MARK: - Headers and Authentication Extension

extension BICURLWrapper {
    
    func setupHeaderCallback(curlPtr: UnsafeMutableRawPointer) {
        let headerCallback: curl_write_callback = { (buffer, size, nitems, userdata) -> Int in
            guard let userdata = userdata else { return Int(size * nitems) }
            let wrapper = Unmanaged<BICURLWrapper>.fromOpaque(userdata).takeUnretainedValue()
            
            guard let buffer = buffer else { return Int(size * nitems) }
            let dataSize = Int(size * nitems)
            guard dataSize > 0 else { return 0 }
            
            let data = Data(bytes: buffer, count: dataSize)
            
            if let headerString = String(data: data, encoding: .utf8) {
                let trimmed = headerString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // HTTP status line
                if trimmed.hasPrefix("HTTP/") {
                    let components = trimmed.components(separatedBy: " ")
                    if components.count >= 3, let statusCode = Int(components[1]) {
                        if statusCode >= 300 && statusCode < 400 {
                            let statusText = components[2...].joined(separator: " ")
                            wrapper.logger.info("[\(wrapper.identifier)] Redirect: HTTP \(statusCode) \(statusText)")
                        }
                    }
                }
                
                // Location header
                if trimmed.lowercased().hasPrefix("location:") {
                    let location = trimmed.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                    wrapper.logger.debug("[\(wrapper.identifier)] Redirect location: \(location)")
                    
                    if let lastCode = wrapper.redirectChain.last?.code {
                        wrapper.redirectChain.append((url: location, code: lastCode))
                    } else {
                        wrapper.redirectChain.append((url: location, code: 302))
                    }
                    
                    wrapper.finalURL = location
                }
                
                // Парсинг и сохранение заголовков
                if trimmed.contains(":") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0]).lowercased()
                        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        wrapper.responseHeaders[key] = value
                    }
                }
            }
            
            return dataSize
        }
        
        _ = curl_easy_setopt_write_function(curlPtr, CURLOPT_HEADERFUNCTION, headerCallback)
        _ = curl_easy_setopt_pointer(curlPtr, CURLOPT_HEADERDATA, Unmanaged.passUnretained(self).toOpaque())
    }
    
    func setupCustomHeaders() {
        guard !options.customHeaders.isEmpty else { return }
        
        for (key, value) in options.customHeaders {
            let headerString = "\(key): \(value)"
            headersList = curl_slist_append(headersList, headerString)
        }
    }
    
    func setupAuthentication(curlPtr: UnsafeMutableRawPointer) {
        guard let auth = options.authentication else { return }
        
        switch auth.type {
        case .basic(let username, let password):
            _ = curl_easy_setopt_int(curlPtr, CURLOPT_HTTPAUTH, Int32(CURLAUTH_BASIC))
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_USERNAME, username)
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_PASSWORD, password)
            
        case .digest(let username, let password):
            _ = curl_easy_setopt_int(curlPtr, CURLOPT_HTTPAUTH, Int32(CURLAUTH_DIGEST))
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_USERNAME, username)
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_PASSWORD, password)
            
        case .bearer(let token):
            let authHeader = "Authorization: Bearer \(token)"
            headersList = curl_slist_append(headersList, authHeader)
            
        case .custom(let header, let value):
            let customHeader = "\(header): \(value)"
            headersList = curl_slist_append(headersList, customHeader)
        }
    }
    
    func setupSSLConfiguration(curlPtr: UnsafeMutableRawPointer) {
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_SSL_VERIFYPEER, 1)
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_SSL_VERIFYHOST, 2)
        
        var sslConfigured = false
        
        if let bundlePath = Bundle.main.path(forResource: "cacert", ofType: "pem") {
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_CAINFO, bundlePath)
            logger.debug("[\(identifier)] Using bundle CA certificates")
            sslConfigured = true
        }
        
        if !sslConfigured {
            let possiblePaths = [
                "/etc/ssl/certs/ca-certificates.crt",
                "/usr/share/curl/curl-ca-bundle.crt",
                "/etc/ssl/cert.pem",
                "/System/Library/OpenSSL/certs/cert.pem"
            ]
            
            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    _ = curl_easy_setopt_string(curlPtr, CURLOPT_CAINFO, path)
                    logger.debug("[\(identifier)] Using system CA certificates: \(path)")
                    sslConfigured = true
                    break
                }
            }
        }
        
        if !sslConfigured {
            logger.warning("[\(identifier)] No CA certificates found")
            _ = curl_easy_setopt_string(curlPtr, CURLOPT_CAPATH, "/System/Library/OpenSSL/certs")
            _ = curl_easy_setopt_int(curlPtr, CURLOPT_SSL_OPTIONS, Int32(CURLSSLOPT_NATIVE_CA))
            
            #if DEBUG
            logger.warning("[\(identifier)] DEBUG: Disabling SSL peer verification")
            _ = curl_easy_setopt_int(curlPtr, CURLOPT_SSL_VERIFYPEER, 0)
            #endif
        }
        
        _ = curl_easy_setopt_int(curlPtr, CURLOPT_SSLVERSION, Int32(CURL_SSLVERSION_TLSv1_2))
        _ = curl_easy_setopt_string(curlPtr, CURLOPT_SSL_CIPHER_LIST, "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS")
    }
}
