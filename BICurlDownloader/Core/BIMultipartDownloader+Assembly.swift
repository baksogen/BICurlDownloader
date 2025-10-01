//
//  BIMultipartDownloader+Assembly.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

// MARK: - File Assembly Extension

extension BIMultipartDownloader {
    
    func assembleFinalFile(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                completion(.failure(BIDownloadError.validationError("Downloader deallocated")))
                return
            }
            
            do {
                // Проверяем все временные файлы
                for part in self.downloadParts.sorted(by: { $0.index < $1.index }) {
                    guard FileManager.default.fileExists(atPath: part.tempFilePath) else {
                        throw BIDownloadError.fileSystemError(NSError(
                            domain: "BICurlDownloader",
                            code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "Part file \(part.index) not found"]
                        ))
                    }
                    
                    let attributes = try FileManager.default.attributesOfItem(atPath: part.tempFilePath)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    
                    if fileSize == 0 {
                        self.logger.warning("[Downloader] Part \(part.index) is empty")
                    }
                }
                
                let finalURL = URL(fileURLWithPath: self.destinationPath)
                let directory = finalURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                
                if FileManager.default.fileExists(atPath: self.destinationPath) {
                    try FileManager.default.removeItem(atPath: self.destinationPath)
                }
                
                if self.downloadParts.count == 1 {
                    // Для одной части просто перемещаем файл
                    let singlePartPath = self.downloadParts[0].tempFilePath
                    try FileManager.default.moveItem(atPath: singlePartPath, toPath: self.destinationPath)
                    self.logger.info("[Downloader] Moved single part file to: \(self.destinationPath)")
                } else {
                    // Собираем файл из частей
                    try self.assembleMultipleParts(to: finalURL)
                }
                
                DispatchQueue.main.async {
                    completion(.success(self.destinationPath))
                }
                
            } catch {
                self.logger.error("[Downloader] Failed to assemble final file: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(BIDownloadError.fileSystemError(error)))
                }
            }
        }
    }
    
    private func assembleMultipleParts(to finalURL: URL) throws {
        FileManager.default.createFile(atPath: destinationPath, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: finalURL)
        defer { fileHandle.closeFile() }
        
        for part in downloadParts.sorted(by: { $0.index < $1.index }) {
            let partURL = URL(fileURLWithPath: part.tempFilePath)
            let partData = try Data(contentsOf: partURL)
            fileHandle.write(partData)
            
            logger.debug("[Downloader] Assembled part \(part.index), size: \(partData.count) bytes")
            try FileManager.default.removeItem(at: partURL)
        }
        
        logger.info("[Downloader] Successfully assembled final file at: \(destinationPath)")
    }
}

// MARK: - BICURLWrapperDelegate

extension BIMultipartDownloader: BICURLWrapperDelegate {
    
    func curlWrapperDidUpdateProgress(_ wrapper: BICURLWrapper, bytesDownloaded: Int64, totalBytes: Int64) {
        if let partIndex = curlWrappers.firstIndex(where: { $0 === wrapper }) {
            downloadParts[partIndex].bytesDownloaded = bytesDownloaded
            downloadParts[partIndex].totalBytes = totalBytes
        }
        
        updateProgress()
    }
    
    func curlWrapperDidComplete(_ wrapper: BICURLWrapper, result: BICURLRequestResult) {
        // Анализируем заголовки (на случай редиректов)
        analyzeHeaders(result)
        
        if let partIndex = curlWrappers.firstIndex(where: { $0 === wrapper }) {
            downloadParts[partIndex].isCompleted = true
            logger.info("[Downloader] Part \(partIndex) completed, downloaded: \(downloadParts[partIndex].bytesDownloaded) bytes")
        }
        
        checkCompletion()
    }
    
    func curlWrapperDidFail(_ wrapper: BICURLWrapper, error: Error) {
        logger.error("[Downloader] Part failed with error: \(error)")
        handleError(error)
    }
}
