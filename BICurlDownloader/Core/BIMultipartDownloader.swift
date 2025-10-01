//
//  BIMultipartDownloader.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

/// Delegate protocol for multipart downloader
protocol BIMultipartDownloaderDelegate: AnyObject {
    func downloaderDidUpdateProgress(_ downloader: BIMultipartDownloader, progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    func downloaderDidComplete(_ downloader: BIMultipartDownloader, filePath: String)
    func downloaderDidFail(_ downloader: BIMultipartDownloader, error: Error)
}

/// Адаптивный загрузчик файлов
class BIMultipartDownloader {
    
    // MARK: - Properties
    
    private var url: URL
    let destinationPath: String
    let options: BIDownloadOptions
    let contentLength: Int64?
    let supportsRangeRequests: Bool
    
    weak var delegate: BIMultipartDownloaderDelegate?
    
    internal var downloadParts: [BIDownloadPart] = []
    internal var curlWrappers: [BICURLWrapper] = []
    
    private let progressLock = NSLock()
    private let stateLock = NSLock()
    
    private var totalBytesDownloaded: Int64 = 0
    private var detectedContentLength: Int64?
    
    private var isRunning = false
    private var isPaused = false
    private var isCancelled = false
    
    internal let logger = BILogger.shared
    private let fileManager = BIFileManager.shared
    
    // MARK: - Initialization
    
    init(url: URL, destinationPath: String, options: BIDownloadOptions, contentLength: Int64?, supportsRangeRequests: Bool) {
        self.url = url
        self.destinationPath = destinationPath
        self.options = options
        self.contentLength = contentLength
        self.supportsRangeRequests = supportsRangeRequests
    }
    
    // MARK: - Public Methods
    
    func start() {
        stateLock.lock()
        guard !isRunning && !isCancelled else {
            stateLock.unlock()
            return
        }
        isRunning = true
        isPaused = false
        stateLock.unlock()
        
        logger.info("[Downloader] Starting adaptive download for: \(url)")
        
        // Проверка места на диске
        if let contentLength = contentLength {
            if !fileManager.hasEnoughSpace(for: contentLength) {
                let error = BIDownloadError.insufficientSpace()
                handleError(error)
                return
            }
        }
        
        // Принимаем решение о многопоточности ДО начала загрузки
        startInitialThread()
    }
    
    func pause() {
        stateLock.lock()
        guard isRunning && !isPaused else {
            stateLock.unlock()
            return
        }
        isPaused = true
        stateLock.unlock()
        
        logger.info("[Downloader] Pausing download")
        curlWrappers.forEach { $0.pause() }
    }
    
    func resume() {
        stateLock.lock()
        guard isRunning && isPaused else {
            stateLock.unlock()
            return
        }
        isPaused = false
        stateLock.unlock()
        
        logger.info("[Downloader] Resuming download")
        curlWrappers.forEach { $0.resume() }
    }
    
    func cancel() {
        stateLock.lock()
        isCancelled = true
        isRunning = false
        stateLock.unlock()
        
        logger.info("[Downloader] Cancelling download")
        curlWrappers.forEach { $0.cancel() }
        cleanupTempFiles()
    }
    
    // MARK: - Private Methods - Initial Thread
    
    private func startInitialThread() {
        // Проверяем условия для многопоточной загрузки ДО начала загрузки
        let minSizeForMultipart: Int64 = 10 * 1024 * 1024 // 10 MB
        
        let shouldUseMultipart = options.enableMultipart &&
                                 supportsRangeRequests &&
                                 contentLength != nil &&
                                 contentLength! > minSizeForMultipart
        
        if shouldUseMultipart {
            logger.info("[Downloader] Starting multipart download with \(options.maxConcurrentStreams) threads")
            startMultipartDownload(totalSize: contentLength!)
        } else {
            logger.info("[Downloader] Starting single-threaded download")
            if !supportsRangeRequests {
                logger.info("[Downloader] Reason: Server doesn't support Range requests")
            } else if contentLength == nil {
                logger.info("[Downloader] Reason: Content length unknown")
            } else if let size = contentLength, size <= minSizeForMultipart {
                logger.info("[Downloader] Reason: File too small (\(size) bytes)")
            } else {
                logger.info("[Downloader] Reason: Multipart disabled in options")
            }
            startSingleThreadDownload()
        }
    }
    
    private func startSingleThreadDownload() {
        // Создаем первую часть - загрузка всего файла
        let part = BIDownloadPart(
            index: 0,
            startByte: 0,
            endByte: -1, // -1 означает до конца файла
            tempFilePath: getTempFilePath(for: 0)
        )
        downloadParts = [part]
        
        // Создаем wrapper
        let wrapper = BICURLWrapper(
            url: url,
            options: options,
            requestType: .download(outputPath: part.tempFilePath, range: nil),
            identifier: "Single-0"
        )
        wrapper.delegate = self
        curlWrappers = [wrapper]
        
        wrapper.start()
    }
    
    private func startMultipartDownload(totalSize: Int64) {
        let threadCount = min(options.maxConcurrentStreams, 8) // Максимум 8 потоков
        let partSize = totalSize / Int64(threadCount)
        let minPartSize: Int64 = 5 * 1024 * 1024 // 5 MB минимум на часть
        
        // Корректируем количество потоков, если части получаются слишком маленькими
        let actualThreadCount = min(threadCount, Int(totalSize / minPartSize))
        let actualPartSize = totalSize / Int64(actualThreadCount)
        
        logger.info("[Downloader] Using \(actualThreadCount) threads, part size: \(actualPartSize) bytes")
        
        detectedContentLength = totalSize
        
        var newParts: [BIDownloadPart] = []
        var newWrappers: [BICURLWrapper] = []
        
        for i in 0..<actualThreadCount {
            let startByte = Int64(i) * actualPartSize
            let endByte: Int64 = (i == actualThreadCount - 1) ? totalSize - 1 : startByte + actualPartSize - 1
            
            let part = BIDownloadPart(
                index: i,
                startByte: startByte,
                endByte: endByte,
                tempFilePath: getTempFilePath(for: i)
            )
            
            newParts.append(part)
            
            let range = "\(startByte)-\(endByte)"
            logger.debug("[Downloader] Part \(i): bytes \(range)")
            
            let wrapper = BICURLWrapper(
                url: url,
                options: options,
                requestType: .download(outputPath: part.tempFilePath, range: range),
                identifier: "Part-\(i)"
            )
            wrapper.delegate = self
            newWrappers.append(wrapper)
        }
        
        downloadParts = newParts
        curlWrappers = newWrappers
        
        // Запускаем все потоки
        curlWrappers.forEach { $0.start() }
        
        logger.info("[Downloader] Started \(actualThreadCount) parallel download threads")
    }
    
    // MARK: - Header Analysis
    
    internal func analyzeHeaders(_ result: BICURLRequestResult) {
        // Этот метод больше не используется для принятия решения о многопоточности
        // Решение принимается в startInitialThread() на основе данных из BIServerCapabilities
        
        logger.debug("[Downloader] Headers received: HTTP \(result.httpResponseCode)")
        
        // Проверка на редирект с новым URL
        if let effectiveURL = result.effectiveURL,
           let newURL = URL(string: effectiveURL),
           newURL.absoluteString != url.absoluteString {
            handleRedirect(to: newURL)
            return
        }
        
        // Обновляем информацию о размере, если она изменилась
        if let detectedSize = result.contentLength {
            if detectedContentLength == nil || detectedContentLength != detectedSize {
                detectedContentLength = detectedSize
                logger.debug("[Downloader] Updated content length: \(detectedSize) bytes")
            }
        }
    }
    
    private func handleRedirect(to newURL: URL) {
        logger.info("[Downloader] Redirect detected from \(url) to \(newURL)")
        logger.info("[Downloader] Restarting download with new URL")
        
        // Отменяем текущую загрузку
        curlWrappers.forEach { $0.cancel() }
        cleanupTempFiles()
        
        // Сбрасываем состояние
        downloadParts.removeAll()
        curlWrappers.removeAll()
        detectedContentLength = nil
        totalBytesDownloaded = 0
        
        // Обновляем URL
        url = newURL
        
        // Перезапускаем загрузку
        startInitialThread()
    }
    
    // MARK: - Helper Methods
    
    private func getTempFilePath(for partIndex: Int) -> String {
        let tempDir = fileManager.getTempDirectory()
        let fileName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        return "\(tempDir)/\(fileName).part\(partIndex).tmp"
    }
    
    internal func updateProgress() {
        progressLock.lock()
        defer { progressLock.unlock() }
        
        let totalDownloaded = downloadParts.reduce(0) { $0 + $1.bytesDownloaded }
        
        // Определяем общий размер файла
        var totalSize: Int64 = 0
        
        if let detected = detectedContentLength, detected > 1 {
            // Используем размер, определенный из заголовков при загрузке
            totalSize = detected
        } else if let initial = contentLength, initial > 1 {
            // Используем размер из начальной проверки (если он адекватный)
            totalSize = initial
        } else {
            // Вычисляем из частей (для multipart)
            for part in downloadParts {
                if part.endByte > 0 {
                    // Если известен диапазон части
                    totalSize += (part.endByte - part.startByte + 1)
                } else {
                    // Если диапазон неизвестен, используем скачанное + ожидаемое
                    totalSize += max(part.totalBytes, part.bytesDownloaded)
                }
            }
        }
        
        // Если размер все еще неизвестен, используем скачанное как минимум
        if totalSize == 0 {
            totalSize = max(1, totalDownloaded)
        }
        
        totalBytesDownloaded = totalDownloaded
        
        let progress = totalSize > 0 ? Double(totalDownloaded) / Double(totalSize) : 0.0
        let progressPercent = String(format: "%.1f", progress * 100)
        
        logger.debug("[Downloader] Progress: \(totalDownloaded)/\(totalSize) bytes (\(progressPercent)%)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.downloaderDidUpdateProgress(
                self,
                progress: progress,
                bytesDownloaded: totalDownloaded,
                totalBytes: totalSize
            )
        }
    }
    
    internal func checkCompletion() {
        let allCompleted = downloadParts.allSatisfy { $0.isCompleted }
        
        guard allCompleted else { return }
        
        logger.info("[Downloader] All parts completed, assembling final file")
        
        assembleFinalFile { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let filePath):
                self.handleCompletion(filePath: filePath)
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    private func handleCompletion(filePath: String) {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
        
        delegate?.downloaderDidComplete(self, filePath: filePath)
    }
    
    internal func handleError(_ error: Error) {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
        
        cleanupTempFiles()
        delegate?.downloaderDidFail(self, error: error)
    }
    
    private func cleanupTempFiles() {
        for part in downloadParts {
            do {
                if FileManager.default.fileExists(atPath: part.tempFilePath) {
                    try FileManager.default.removeItem(atPath: part.tempFilePath)
                }
            } catch {
                logger.warning("[Downloader] Failed to cleanup temp file: \(error)")
            }
        }
    }
}

// MARK: - BIDownloadPart

struct BIDownloadPart {
    let index: Int
    let startByte: Int64
    let endByte: Int64
    let tempFilePath: String
    
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var isCompleted: Bool
    
    init(index: Int, startByte: Int64, endByte: Int64, tempFilePath: String, bytesDownloaded: Int64 = 0, totalBytes: Int64 = 0, isCompleted: Bool = false) {
        self.index = index
        self.startByte = startByte
        self.endByte = endByte
        self.tempFilePath = tempFilePath
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.isCompleted = isCompleted
    }
}
