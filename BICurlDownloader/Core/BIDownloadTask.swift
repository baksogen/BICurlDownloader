//
//  BIDownloadTask.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

/// Download task
@objc public class BIDownloadTask: NSObject {
    
    // MARK: - Properties
    
    @objc public let id: String
    private var _url: URL
    @objc public let destinationPath: String
    public let options: BIDownloadOptions
    
    @objc public var url: URL {
        return _url
    }
    
    private var _progress = Progress(totalUnitCount: 100)
    private var _state: BIDownloadState = .pending
    private let stateLock = NSLock()
    
    @objc public weak var delegate: BIDownloadDelegate?
    
    private weak var manager: BIDownloadManager?
    private var downloader: BIMultipartDownloader?
    private var serverCapabilities: BIServerCapabilitiesInfo?
    private var capabilitiesChecker: BIServerCapabilities?
    
    private let logger = BILogger.shared
    
    // MARK: - Public Properties
    
    @objc public var progress: Progress {
        return _progress
    }
    
    @objc public var state: BIDownloadState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }
    
    @objc public var taskId: String {
        return id
    }
    
    /// Custom note/metadata for this task
    @objc public var note: String?
    
    // MARK: - Initialization
    
    internal init(id: String, url: URL, destinationPath: String, options: BIDownloadOptions, note: String? = nil) {
        self.id = id
        self._url = url
        self.destinationPath = destinationPath
        self.options = options
        self.note = note
        
        super.init()
        setupProgress()
    }
    
    // MARK: - Public Methods
    
    @objc public func pause() {
        logger.info("[Task \(id)] Pausing")
        
        guard canTransition(to: .paused) else {
            logger.warning("[Task \(id)] Cannot pause in current state: \(state)")
            return
        }
        
        downloader?.pause()
        updateState(.paused)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidPause(task: self)
        
        manager?.taskDidPause(self)
    }
    
    @objc public func resume() {
        logger.info("[Task \(id)] Resuming")
        
        guard state == .paused else {
            logger.warning("[Task \(id)] Cannot resume in current state: \(state)")
            return
        }
        
        downloader?.resume()
        updateState(.downloading)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidResume(task: self)
    }
    
    @objc public func cancel() {
        logger.info("[Task \(id)] Cancelling")
        
        guard canTransition(to: .cancelled) else {
            logger.warning("[Task \(id)] Cannot cancel in current state: \(state)")
            return
        }
        
        downloader?.cancel()
        updateState(.cancelled)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidCancel(task: self)
        
        manager?.taskDidCancel(self)
        cleanup()
    }
    
    // MARK: - Internal Methods
    
    internal func start(manager: BIDownloadManager) {
        self.manager = manager
        
        logger.info("[Task \(id)] Starting for URL: \(url)")
        
        guard canTransition(to: .downloading) else {
            logger.error("[Task \(id)] Cannot start in current state: \(state)")
            let error = BIDownloadError.validationError("Invalid state for starting download")
            handleError(error)
            return
        }
        
        updateState(.downloading)
        delegate?.downloadDidStart(self)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidStart(task: self)
        
        // Проверяем возможности сервера
        checkServerCapabilities { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let capabilities):
                self.serverCapabilities = capabilities
                self.startDownload(with: capabilities)
                
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupProgress() {
        _progress.kind = .file
        _progress.fileOperationKind = .downloading
        _progress.cancellationHandler = { [weak self] in
            self?.cancel()
        }
    }
    
    private func canTransition(to newState: BIDownloadState) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        switch (_state, newState) {
        case (.pending, .downloading),
             (.downloading, .paused),
             (.downloading, .completed),
             (.downloading, .cancelled),
             (.paused, .downloading),
             (.paused, .cancelled),
             (.pending, .cancelled),
             (.downloading, .failed),
             (.paused, .failed):
            return true
        default:
            return false
        }
    }
    
    private func updateState(_ newState: BIDownloadState) {
        stateLock.lock()
        let oldState = _state
        _state = newState
        stateLock.unlock()
        
        logger.info("[Task \(id)] State changed: \(oldState) -> \(newState)")
    }
    
    private func checkServerCapabilities(completion: @escaping (Result<BIServerCapabilitiesInfo, Error>) -> Void) {
        logger.info("[Task \(id)] checkServerCapabilities started")
        
        let checker = BIServerCapabilities()
        self.capabilitiesChecker = checker
        
        logger.info("[Task \(id)] Calling checker.check...")
        
        checker.check(url: _url, options: options) { [weak self] result in
            guard let self = self else {
                BILogger.shared.warning("[Task ?] Self is nil in checkServerCapabilities callback")
                return
            }
            
            self.logger.info("[Task \(self.id)] checkServerCapabilities callback received")
            
            DispatchQueue.main.async {
                self.logger.info("[Task \(self.id)] Processing capabilities result on main queue")
                
                switch result {
                case .success(let capabilities):
                    // Проверяем редирект
                    if let effectiveURL = capabilities.effectiveURL,
                       let newURL = URL(string: effectiveURL),
                       newURL.absoluteString != self._url.absoluteString {
                        
                        self.logger.info("[Task \(self.id)] Redirect detected: \(effectiveURL)")
                        self._url = newURL
                    }
                    
                    self.logger.info("[Task \(self.id)] Calling completion with success")
                    completion(result)
                    
                case .failure:
                    self.logger.info("[Task \(self.id)] Calling completion with failure")
                    completion(result)
                }
                
                self.logger.info("[Task \(self.id)] Clearing capabilitiesChecker")
                self.capabilitiesChecker = nil
            }
        }
    }
    
    private func startDownload(with capabilities: BIServerCapabilitiesInfo) {
        // Определяем стратегию загрузки
        let minMultipartSize: Int64 = 5 * 1024 * 1024 // 5 MB
        let hasContentLength = capabilities.contentLength != nil && capabilities.contentLength! > 0
        let isLargeFile = hasContentLength && capabilities.contentLength! >= minMultipartSize
        let useMultipart = options.enableMultipart && capabilities.supportsRangeRequests && isLargeFile
        
        if hasContentLength {
            logger.info("[Task \(id)] File size: \(capabilities.contentLength!) bytes")
        } else {
            logger.info("[Task \(id)] File size unknown")
        }
        
        logger.info("[Task \(id)] Range requests: \(capabilities.supportsRangeRequests)")
        logger.info("[Task \(id)] Download mode: \(useMultipart ? "adaptive multipart" : "single thread")")
        
        // Создаем downloader
        downloader = BIMultipartDownloader(
            url: _url,
            destinationPath: destinationPath,
            options: options,
            contentLength: capabilities.contentLength,
            supportsRangeRequests: capabilities.supportsRangeRequests
        )
        
        downloader?.delegate = self
        downloader?.start()
    }
    
    private func handleError(_ error: Error) {
        logger.error("[Task \(id)] Failed with error: \(error)")
        
        updateState(.failed)
        delegate?.downloadDidFail(self, error: error)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidFail(task: self, error: error)
        
        manager?.taskDidFail(self, error: error)
        cleanup()
    }
    
    private func handleCompletion(filePath: String) {
        logger.info("[Task \(id)] Completed successfully")
        
        updateState(.completed)
        delegate?.downloadDidComplete(self, filePath: filePath)
        
        // Post notification
        BIDownloadNotificationCenter.shared.postDidComplete(task: self, filePath: filePath)
        
        manager?.taskDidComplete(self)
        cleanup()
    }
    
    private func cleanup() {
        downloader = nil
        serverCapabilities = nil
        capabilitiesChecker = nil
    }
}

// MARK: - BIMultipartDownloaderDelegate

extension BIDownloadTask: BIMultipartDownloaderDelegate {
    
    func downloaderDidUpdateProgress(_ downloader: BIMultipartDownloader, progress: Double, bytesDownloaded: Int64, totalBytes: Int64) {
        _progress.totalUnitCount = totalBytes
        _progress.completedUnitCount = bytesDownloaded
        
        delegate?.downloadDidProgress(self, progress: progress)
        
        // Post notification (throttled internally)
        BIDownloadNotificationCenter.shared.postDidUpdateProgress(
            task: self,
            progress: progress,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes
        )
        
        logger.verbose("[Task \(id)] Progress: \(String(format: "%.1f", progress * 100))%")
    }
    
    func downloaderDidComplete(_ downloader: BIMultipartDownloader, filePath: String) {
        handleCompletion(filePath: filePath)
    }
    
    func downloaderDidFail(_ downloader: BIMultipartDownloader, error: Error) {
        handleError(error)
    }
}
