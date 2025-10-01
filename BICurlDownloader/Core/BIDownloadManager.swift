//
//  BIDownloadManager.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import AVFoundation
import UIKit

/// Main download manager
@objc public class BIDownloadManager: NSObject {
    
    // MARK: - Singleton
    
    @objc public static let shared = BIDownloadManager()
    
    // MARK: - Properties
    
    private var configuration: BIDownloadManagerConfiguration
    private var activeTasks: [String: BIDownloadTask] = [:]
    private var taskQueue: [BIDownloadTask] = []
    private let taskQueueLock = NSLock()
    private let activeTasksLock = NSLock()
    
    private lazy var backgroundAudioManager = BIBackgroundAudioManager()
    private lazy var networkMonitor = BINetworkMonitor()
    private lazy var logger = BILogger.shared
    
    // MARK: - Initialization
    
    private override init() {
        self.configuration = BIDownloadManagerConfiguration()
        super.init()
        
        // Ensure framework initialization
        BIDownloadManager.ensureFrameworkInitialized()
        
        setupNotifications()
    }
    
    // MARK: - Public API
    
    /// Configure manager
    @objc public func configure(_ configuration: BIDownloadManagerConfiguration) {
        self.configuration = configuration
        logger.configure(level: configuration.logLevel, enabled: configuration.enableLogging)
        logger.info("BIDownloadManager configured with max concurrent downloads: \(configuration.maxConcurrentDownloads)")
    }
    
    /// Create new download task
    @objc public func download(
        url: URL,
        destinationPath: String,
        options: BIDownloadOptions = .default
    ) -> BIDownloadTask {
        return download(url: url, destinationPath: destinationPath, options: options, note: nil)
    }
    
    /// Create new download task with custom note
    @objc public func download(
        url: URL,
        destinationPath: String,
        options: BIDownloadOptions = .default,
        note: String?
    ) -> BIDownloadTask {
        
        let taskId = UUID().uuidString
        let task = BIDownloadTask(
            id: taskId,
            url: url,
            destinationPath: destinationPath,
            options: options,
            note: note
        )
        
        // Add task to queue
        taskQueueLock.lock()
        taskQueue.append(task)
        taskQueueLock.unlock()
        
        logger.info("Created download task \(taskId) for URL: \(url)")
        
        // Try to start task if slots available
        processQueue()
        
        return task
    }
    
    /// Pause all downloads
    @objc public func pauseAll() {
        logger.info("Pausing all downloads")
        
        activeTasksLock.lock()
        let tasks = Array(activeTasks.values)
        activeTasksLock.unlock()
        
        tasks.forEach { $0.pause() }
    }
    
    /// Resume all downloads
    @objc public func resumeAll() {
        logger.info("Resuming all downloads")
        
        activeTasksLock.lock()
        let tasks = Array(activeTasks.values)
        activeTasksLock.unlock()
        
        tasks.forEach { $0.resume() }
        
        // Process queue to start new tasks
        processQueue()
    }
    
    /// Cancel all downloads
    @objc public func cancelAll() {
        logger.info("Cancelling all downloads")
        
        // Cancel active tasks
        activeTasksLock.lock()
        let activeTasks = Array(self.activeTasks.values)
        self.activeTasks.removeAll()
        activeTasksLock.unlock()
        
        activeTasks.forEach { $0.cancel() }
        
        // Cancel queued tasks
        taskQueueLock.lock()
        let queuedTasks = taskQueue
        taskQueue.removeAll()
        taskQueueLock.unlock()
        
        queuedTasks.forEach { $0.cancel() }
        
        // Stop background audio
        backgroundAudioManager.stopBackgroundAudio()
    }
    
    /// Check if background audio is available for background downloads
    @objc public func checkBackgroundAudioAvailability() -> Bool {
        let result = backgroundAudioManager.checkBackgroundAudioCapability()
        return result.available
    }
    
    /// Get detailed information about background audio capability
    public func getBackgroundAudioCapabilityInfo() -> (available: Bool, reason: String?) {
        return backgroundAudioManager.checkBackgroundAudioCapability()
    }
    
    /// Get all active download tasks
    @objc public func getActiveTasks() -> [BIDownloadTask] {
        activeTasksLock.lock()
        let tasks = Array(activeTasks.values)
        activeTasksLock.unlock()
        return tasks
    }
    
    /// Get all queued download tasks
    @objc public func getQueuedTasks() -> [BIDownloadTask] {
        taskQueueLock.lock()
        let tasks = Array(taskQueue)
        taskQueueLock.unlock()
        return tasks
    }
    
    /// Get all tasks (active + queued)
    @objc public func getAllTasks() -> [BIDownloadTask] {
        return getActiveTasks() + getQueuedTasks()
    }
    
    /// Find task by ID
    @objc public func getTask(byId taskId: String) -> BIDownloadTask? {
        activeTasksLock.lock()
        if let task = activeTasks[taskId] {
            activeTasksLock.unlock()
            return task
        }
        activeTasksLock.unlock()
        
        taskQueueLock.lock()
        let task = taskQueue.first { $0.id == taskId }
        taskQueueLock.unlock()
        return task
    }
    
    /// Find tasks by URL
    @objc public func getTasks(forURL url: URL) -> [BIDownloadTask] {
        let allTasks = getAllTasks()
        return allTasks.filter { $0.url.absoluteString == url.absoluteString }
    }
    
    /// Find tasks by note
    @objc public func getTasks(withNote note: String) -> [BIDownloadTask] {
        let allTasks = getAllTasks()
        return allTasks.filter { $0.note == note }
    }
    
    /// Get download statistics
    public func getDownloadStatistics() -> BIDownloadStatistics {
        activeTasksLock.lock()
        let activeCount = activeTasks.count
        activeTasksLock.unlock()
        
        taskQueueLock.lock()
        let queuedCount = taskQueue.count
        taskQueueLock.unlock()
        
        return BIDownloadStatistics(
            activeDownloads: activeCount,
            queuedDownloads: queuedCount,
            maxConcurrent: configuration.maxConcurrentDownloads
        )
    }
    
    // MARK: - Internal Methods
    
    internal func taskDidComplete(_ task: BIDownloadTask) {
        logger.info("Task \(task.id) completed")
        removeActiveTask(task)
        postManagerStateNotification()
        processQueue()
        
        // Check if background audio should be stopped
        if activeTasks.isEmpty && taskQueue.isEmpty {
            backgroundAudioManager.stopBackgroundAudio()
        }
    }
    
    internal func taskDidFail(_ task: BIDownloadTask, error: Error) {
        logger.error("Task \(task.id) failed: \(error)")
        removeActiveTask(task)
        postManagerStateNotification()
        processQueue()
    }
    
    internal func taskDidCancel(_ task: BIDownloadTask) {
        logger.info("Task \(task.id) cancelled")
        removeActiveTask(task)
        postManagerStateNotification()
        processQueue()
    }
    
    internal func taskDidPause(_ task: BIDownloadTask) {
        logger.info("Task \(task.id) paused")
        removeActiveTask(task)
        postManagerStateNotification()
        processQueue()
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        logger.info("App entering foreground")
        // Logic can be added here to update download states
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("App entering background")
        // Start background audio if there are active downloads
        if !activeTasks.isEmpty {
            startBackgroundModeIfNeeded()
        }
    }
    
    private func processQueue() {
        taskQueueLock.lock()
        defer { taskQueueLock.unlock() }
        
        activeTasksLock.lock()
        let currentActiveCount = activeTasks.count
        activeTasksLock.unlock()
        
        let availableSlots = configuration.maxConcurrentDownloads - currentActiveCount
        
        guard availableSlots > 0, !taskQueue.isEmpty else {
            return
        }
        
        let tasksToStart = min(availableSlots, taskQueue.count)
        let tasks = Array(taskQueue.prefix(tasksToStart))
        taskQueue.removeFirst(tasksToStart)
        
        taskQueueLock.unlock()
        
        for task in tasks {
            startTask(task)
        }
        
        taskQueueLock.lock()
    }
    
    private func startTask(_ task: BIDownloadTask) {
        activeTasksLock.lock()
        activeTasks[task.id] = task
        activeTasksLock.unlock()
        
        // Start background audio if needed
        if task.options.enableBackgroundAudio {
            startBackgroundModeIfNeeded()
        }
        
        // Start task
        task.start(manager: self)
        
        logger.info("Started task \(task.id)")
        
        // Post notification about manager state change
        postManagerStateNotification()
    }
    
    private func removeActiveTask(_ task: BIDownloadTask) {
        activeTasksLock.lock()
        activeTasks.removeValue(forKey: task.id)
        activeTasksLock.unlock()
    }
    
    private func startBackgroundModeIfNeeded() {
        guard !activeTasks.isEmpty else { return }
        
        // Check if at least one task requires background mode
        let needsBackground = activeTasks.values.contains { $0.options.enableBackgroundAudio }
        
        if needsBackground {
            backgroundAudioManager.startBackgroundAudio()
        }
    }
    
    private func postManagerStateNotification() {
        activeTasksLock.lock()
        let activeCount = activeTasks.count
        activeTasksLock.unlock()
        
        taskQueueLock.lock()
        let queuedCount = taskQueue.count
        taskQueueLock.unlock()
        
        BIDownloadNotificationCenter.shared.postManagerStateDidChange(
            activeTasksCount: activeCount,
            queuedTasksCount: queuedCount
        )
    }
}

// MARK: - BIDownloadStatistics

public struct BIDownloadStatistics {
    public let activeDownloads: Int
    public let queuedDownloads: Int
    public let maxConcurrent: Int
    
    public var availableSlots: Int {
        return max(0, maxConcurrent - activeDownloads)
    }
}

// MARK: - UIApplication Extension for iOS 13+ compatibility

extension UIApplication {
    static var willEnterForegroundNotification: NSNotification.Name {
        if #available(iOS 13.0, *) {
            return UIScene.willEnterForegroundNotification
        } else {
            return UIApplication.willEnterForegroundNotification
        }
    }
    
    static var didEnterBackgroundNotification: NSNotification.Name {
        if #available(iOS 13.0, *) {
            return UIScene.didEnterBackgroundNotification
        } else {
            return UIApplication.didEnterBackgroundNotification
        }
    }
}
