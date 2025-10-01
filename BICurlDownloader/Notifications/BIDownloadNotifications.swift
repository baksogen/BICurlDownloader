//
//  BIDownloadNotifications.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

/// Notification names for download events
@objc public class BIDownloadNotification: NSObject {
    
    // MARK: - Notification Names
    
    /// Posted when a download task starts
    /// UserInfo contains: taskId, url, destinationPath, note (optional)
    @objc public static let didStart = Notification.Name("BIDownloadNotification.didStart")
    
    /// Posted when download progress updates (throttled to avoid spam)
    /// UserInfo contains: taskId, progress, bytesDownloaded, totalBytes, url, note (optional)
    @objc public static let didUpdateProgress = Notification.Name("BIDownloadNotification.didUpdateProgress")
    
    /// Posted when a download completes successfully
    /// UserInfo contains: taskId, filePath, url, note (optional)
    @objc public static let didComplete = Notification.Name("BIDownloadNotification.didComplete")
    
    /// Posted when a download fails
    /// UserInfo contains: taskId, error, url, note (optional)
    @objc public static let didFail = Notification.Name("BIDownloadNotification.didFail")
    
    /// Posted when a download is paused
    /// UserInfo contains: taskId, url, progress, note (optional)
    @objc public static let didPause = Notification.Name("BIDownloadNotification.didPause")
    
    /// Posted when a download is resumed
    /// UserInfo contains: taskId, url, progress, note (optional)
    @objc public static let didResume = Notification.Name("BIDownloadNotification.didResume")
    
    /// Posted when a download is cancelled
    /// UserInfo contains: taskId, url, note (optional)
    @objc public static let didCancel = Notification.Name("BIDownloadNotification.didCancel")
    
    /// Posted when download manager state changes (active tasks count)
    /// UserInfo contains: activeTasksCount, queuedTasksCount
    @objc public static let managerStateDidChange = Notification.Name("BIDownloadNotification.managerStateDidChange")
    
    // MARK: - UserInfo Keys
    
    /// Key for task ID in userInfo dictionary
    @objc public static let taskIdKey = "taskId"
    
    /// Key for URL in userInfo dictionary
    @objc public static let urlKey = "url"
    
    /// Key for destination path in userInfo dictionary
    @objc public static let destinationPathKey = "destinationPath"
    
    /// Key for file path (completed download) in userInfo dictionary
    @objc public static let filePathKey = "filePath"
    
    /// Key for progress (0.0 to 1.0) in userInfo dictionary
    @objc public static let progressKey = "progress"
    
    /// Key for bytes downloaded in userInfo dictionary
    @objc public static let bytesDownloadedKey = "bytesDownloaded"
    
    /// Key for total bytes in userInfo dictionary
    @objc public static let totalBytesKey = "totalBytes"
    
    /// Key for error in userInfo dictionary
    @objc public static let errorKey = "error"
    
    /// Key for custom note in userInfo dictionary
    @objc public static let noteKey = "note"
    
    /// Key for active tasks count in userInfo dictionary
    @objc public static let activeTasksCountKey = "activeTasksCount"
    
    /// Key for queued tasks count in userInfo dictionary
    @objc public static let queuedTasksCountKey = "queuedTasksCount"
    
    /// Key for download task object in userInfo dictionary
    @objc public static let taskKey = "task"
}

/// Helper class for posting download notifications
internal class BIDownloadNotificationCenter {
    
    static let shared = BIDownloadNotificationCenter()
    
    private let logger = BILogger.shared
    private let notificationCenter = NotificationCenter.default
    
    // Throttling for progress notifications
    private var lastProgressNotificationTime: [String: Date] = [:]
    private let progressThrottleInterval: TimeInterval = 0.5 // 500ms
    private let throttleLock = NSLock()
    
    private init() {}
    
    // MARK: - Post Notifications
    
    func postDidStart(task: BIDownloadTask) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.destinationPathKey: task.destinationPath,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didStart, userInfo: userInfo)
        logger.debug("[Notifications] Posted didStart for task \(task.id)")
    }
    
    func postDidUpdateProgress(task: BIDownloadTask, progress: Double, bytesDownloaded: Int64, totalBytes: Int64) {
        // Throttle progress notifications
        throttleLock.lock()
        let taskId = task.id
        let now = Date()
        
        if let lastTime = lastProgressNotificationTime[taskId] {
            if now.timeIntervalSince(lastTime) < progressThrottleInterval {
                throttleLock.unlock()
                return
            }
        }
        
        lastProgressNotificationTime[taskId] = now
        throttleLock.unlock()
        
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: taskId,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.progressKey: progress,
            BIDownloadNotification.bytesDownloadedKey: bytesDownloaded,
            BIDownloadNotification.totalBytesKey: totalBytes,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didUpdateProgress, userInfo: userInfo)
    }
    
    func postDidComplete(task: BIDownloadTask, filePath: String) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.filePathKey: filePath,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didComplete, userInfo: userInfo)
        logger.debug("[Notifications] Posted didComplete for task \(task.id)")
        
        // Clean up throttle data
        throttleLock.lock()
        lastProgressNotificationTime.removeValue(forKey: task.id)
        throttleLock.unlock()
    }
    
    func postDidFail(task: BIDownloadTask, error: Error) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.errorKey: error,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didFail, userInfo: userInfo)
        logger.debug("[Notifications] Posted didFail for task \(task.id)")
        
        // Clean up throttle data
        throttleLock.lock()
        lastProgressNotificationTime.removeValue(forKey: task.id)
        throttleLock.unlock()
    }
    
    func postDidPause(task: BIDownloadTask) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.progressKey: task.progress.fractionCompleted,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didPause, userInfo: userInfo)
        logger.debug("[Notifications] Posted didPause for task \(task.id)")
    }
    
    func postDidResume(task: BIDownloadTask) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.progressKey: task.progress.fractionCompleted,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didResume, userInfo: userInfo)
        logger.debug("[Notifications] Posted didResume for task \(task.id)")
    }
    
    func postDidCancel(task: BIDownloadTask) {
        var userInfo: [String: Any] = [
            BIDownloadNotification.taskIdKey: task.id,
            BIDownloadNotification.urlKey: task.url.absoluteString,
            BIDownloadNotification.taskKey: task
        ]
        
        if let note = task.note {
            userInfo[BIDownloadNotification.noteKey] = note
        }
        
        post(name: BIDownloadNotification.didCancel, userInfo: userInfo)
        logger.debug("[Notifications] Posted didCancel for task \(task.id)")
        
        // Clean up throttle data
        throttleLock.lock()
        lastProgressNotificationTime.removeValue(forKey: task.id)
        throttleLock.unlock()
    }
    
    func postManagerStateDidChange(activeTasksCount: Int, queuedTasksCount: Int) {
        let userInfo: [String: Any] = [
            BIDownloadNotification.activeTasksCountKey: activeTasksCount,
            BIDownloadNotification.queuedTasksCountKey: queuedTasksCount
        ]
        
        post(name: BIDownloadNotification.managerStateDidChange, userInfo: userInfo)
    }
    
    // MARK: - Private Methods
    
    private func post(name: Notification.Name, userInfo: [String: Any]) {
        DispatchQueue.main.async {
            self.notificationCenter.post(name: name, object: nil, userInfo: userInfo)
        }
    }
}
