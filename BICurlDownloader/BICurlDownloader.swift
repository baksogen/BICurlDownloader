//
//  BICurlDownloader.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import UIKit
import AVFoundation
import Curl

// MARK: - Objective-C Compatibility

/// Objective-C compatible class for download options
@objc public class BIDownloadOptions: NSObject {
    @objc public var maxConcurrentStreams: Int = 4
    @objc public var enableBackgroundAudio: Bool = true
    @objc public var allowsCellularAccess: Bool = true
    @objc public var timeoutInterval: TimeInterval = 60
    @objc public var enableMultipart: Bool = true
    @objc public var authentication: BIAuthenticationOptions? = nil
    @objc public var customHeaders: [String: String] = [:]
    @objc public var userAgent: String = "BICurlDownloader/1.0"
    @objc public var sslVerification: Bool = true
    
    @objc public static let `default`: BIDownloadOptions = BIDownloadOptions()
    
    @objc public override init() {
        super.init()
    }
    
    @objc public init(enableBackgroundAudio: Bool, enableMultipart: Bool, timeoutInterval: TimeInterval) {
        self.enableBackgroundAudio = enableBackgroundAudio
        self.enableMultipart = enableMultipart
        self.timeoutInterval = timeoutInterval
        super.init()
    }
    
    @objc public init(userAgent: String) {
        self.userAgent = userAgent
        super.init()
    }
}

/// Authentication types for Objective-C
@objc public enum BIAuthType: Int {
    case basic = 0
    case digest = 1
    case bearer = 2
    case custom = 3
}

/// Objective-C compatible class for authentication options
@objc public class BIAuthenticationOptions: NSObject {
    @objc public let authType: BIAuthType
    @objc public let username: String?
    @objc public let password: String?
    @objc public let token: String?
    @objc public let headerName: String?
    @objc public let headerValue: String?
    
    @objc public init(basicWithUsername username: String, password: String) {
        self.authType = .basic
        self.username = username
        self.password = password
        self.token = nil
        self.headerName = nil
        self.headerValue = nil
        super.init()
    }
    
    @objc public init(digestWithUsername username: String, password: String) {
        self.authType = .digest
        self.username = username
        self.password = password
        self.token = nil
        self.headerName = nil
        self.headerValue = nil
        super.init()
    }
    
    @objc public init(bearerToken token: String) {
        self.authType = .bearer
        self.username = nil
        self.password = nil
        self.token = token
        self.headerName = nil
        self.headerValue = nil
        super.init()
    }
    
    @objc public init(customWithHeader headerName: String, value headerValue: String) {
        self.authType = .custom
        self.username = nil
        self.password = nil
        self.token = nil
        self.headerName = headerName
        self.headerValue = headerValue
        super.init()
    }
    
    // Internal Swift enum for compatibility with existing code
    internal enum AuthType {
        case basic(username: String, password: String)
        case digest(username: String, password: String)
        case bearer(token: String)
        case custom(header: String, value: String)
    }
    
    internal var type: AuthType {
        switch authType {
        case .basic:
            return .basic(username: username!, password: password!)
        case .digest:
            return .digest(username: username!, password: password!)
        case .bearer:
            return .bearer(token: token!)
        case .custom:
            return .custom(header: headerName!, value: headerValue!)
        }
    }
}

/// Download states for Objective-C
@objc public enum BIDownloadState: Int {
    case pending = 0
    case downloading = 1
    case paused = 2
    case completed = 3
    case failed = 4
    case cancelled = 5
}

/// Objective-C compatible delegate protocol
@objc public protocol BIDownloadDelegate: AnyObject {
    @objc func downloadDidStart(_ task: BIDownloadTask)
    @objc func downloadDidProgress(_ task: BIDownloadTask, progress: Double)
    @objc func downloadDidComplete(_ task: BIDownloadTask, filePath: String)
    @objc func downloadDidFail(_ task: BIDownloadTask, error: Error)
}

/// Objective-C compatible configuration class
@objc public class BIDownloadManagerConfiguration: NSObject {
    @objc public var maxConcurrentDownloads: Int = 3
    @objc public var defaultTimeoutInterval: TimeInterval = 60
    @objc public var enableLogging: Bool = false
    @objc public var logLevel: BILogLevel = .info
    @objc public var cacheDirectory: String = "BICurlDownloads"
    
    @objc public override init() {
        super.init()
    }
    
    @objc public init(enableLogging: Bool, logLevel: BILogLevel, maxConcurrentDownloads: Int) {
        self.enableLogging = enableLogging
        self.logLevel = logLevel
        self.maxConcurrentDownloads = maxConcurrentDownloads
        super.init()
    }
}

/// Logging levels for Objective-C
@objc public enum BILogLevel: Int, CaseIterable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5
}

/// Framework error codes for Objective-C
@objc public enum BIDownloadErrorCode: Int {
    case invalidURL = 1001
    case networkError = 1002
    case fileSystemError = 1003
    case curlError = 1004
    case audioSessionError = 1005
    case validationError = 1006
    case authenticationError = 1007
    case serverError = 1008
    case rangeNotSupported = 1009
    case insufficientSpace = 1010
}

/// Objective-C compatible error class
@objc public class BIDownloadError: NSError, @unchecked Sendable {
    
    @objc public class func invalidURL() -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.invalidURL.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Invalid URL provided"
        ])
    }
    
    @objc public class func networkError(_ underlyingError: Error) -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.networkError.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Network error: \(underlyingError.localizedDescription)",
            NSUnderlyingErrorKey: underlyingError
        ])
    }
    
    @objc public class func fileSystemError(_ underlyingError: Error) -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.fileSystemError.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "File system error: \(underlyingError.localizedDescription)",
            NSUnderlyingErrorKey: underlyingError
        ])
    }
    
    @objc public class func curlError(code: Int, message: String) -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.curlError.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "CURL error (\(code)): \(message)",
            "CURLCode": code,
            "CURLMessage": message
        ])
    }
    
    @objc public class func validationError(_ message: String) -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.validationError.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Validation error: \(message)"
        ])
    }
    
    @objc public class func rangeNotSupported() -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.rangeNotSupported.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Server does not support range requests"
        ])
    }
    
    @objc public class func insufficientSpace() -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.insufficientSpace.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Insufficient disk space"
        ])
    }
    
    @objc public class func serverError(code: Int, message: String) -> BIDownloadError {
        return BIDownloadError(domain: "BICurlDownloader", code: BIDownloadErrorCode.serverError.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Server error (\(code)): \(message)",
            "ServerCode": code,
            "ServerMessage": message
        ])
    }
}

// MARK: - Swift-only API (internal types)

/// Swift enum for internal use
internal enum BIDownloadErrorSwift: Error {
    case invalidURL
    case networkError(Error)
    case fileSystemError(Error)
    case curlError(Int, String)
    case audioSessionError(Error)
    case validationError(String)
    case authenticationError(String)
    case serverError(Int, String)
    case rangeNotSupported
    case insufficientSpace
}

extension BIDownloadErrorSwift: LocalizedError {
    internal var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "File system error: \(error.localizedDescription)"
        case .curlError(let code, let message):
            return "CURL error (\(code)): \(message)"
        case .audioSessionError(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .rangeNotSupported:
            return "Server does not support range requests"
        case .insufficientSpace:
            return "Insufficient disk space"
        }
    }
}

// MARK: - Framework Information

/// Framework version information for Objective-C
@objc public class BICurlDownloaderInfo: NSObject {
    @objc public static let frameworkVersion = "1.0.0"
    @objc public static let build = "1"
    @objc public static let name = "BICurlDownloader"
    
    /// Get full framework information
    @objc public static var fullVersion: String {
        return "\(name) v\(frameworkVersion) (\(build))"
    }
    
    /// Get User-Agent string
    @objc public static var userAgent: String {
        return "\(name)/\(frameworkVersion)"
    }
    
    /// Check compatibility with current iOS version
    @objc public static var isCompatible: Bool {
        if #available(iOS 13.0, *) {
            return true
        } else {
            return false
        }
    }
    
    /// Get information about supported features
    @objc public static var supportedFeatures: [String] {
        var features = ["cURL Integration", "Multipart Downloads", "Authentication"]
        
        if #available(iOS 13.0, *) {
            features.append("Background Audio")
        }
        
        if #available(iOS 12.0, *) {
            features.append("Network Monitoring")
        }
        
        return features
    }
}

// MARK: - Objective-C Compatibility for Download Manager

/// Objective-C compatible methods for BIDownloadManager
extension BIDownloadManager {
    
    /// Objective-C version of quickDownload
    @objc public func quickDownloadFromString(
        _ urlString: String,
        destinationPath: String,
        completion: @escaping (String?, Error?) -> Void
    ) -> BIDownloadTask? {
        
        guard let url = URL(string: urlString) else {
            completion(nil, BIDownloadError.invalidURL())
            return nil
        }
        
        let task = download(url: url, destinationPath: destinationPath)
        
        // Create simple delegate for completion block
        let delegate = ObjCQuickDownloadDelegate { success, error in
            if let error = error {
                completion(nil, error)
            } else {
                completion(success, nil)
            }
        }
        task.delegate = delegate
        
        // Save delegate reference in associated object
        objc_setAssociatedObject(task, &AssociatedKeys.objcQuickDelegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        return task
    }
    
    /// Objective-C version of download with NSURL
    @objc public func downloadFromURL(
        _ url: NSURL,
        destinationPath: String,
        options: BIDownloadOptions? = nil
    ) -> BIDownloadTask {
        let swiftURL = url as URL
        let downloadOptions = options ?? BIDownloadOptions.default
        return download(url: swiftURL, destinationPath: destinationPath, options: downloadOptions)
    }
}

// MARK: - Objective-C Quick Download Delegate

private class ObjCQuickDownloadDelegate: NSObject, BIDownloadDelegate {
    
    private let completion: (String?, Error?) -> Void
    
    init(completion: @escaping (String?, Error?) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func downloadDidStart(_ task: BIDownloadTask) {
        // Do nothing
    }
    
    func downloadDidProgress(_ task: BIDownloadTask, progress: Double) {
        // Do nothing
    }
    
    func downloadDidComplete(_ task: BIDownloadTask, filePath: String) {
        completion(filePath, nil)
    }
    
    
    func downloadDidFail(_ task: BIDownloadTask, error: Error) {
        completion(nil, error)
    }
}

// MARK: - Convenience Extensions

extension BIDownloadManager {
    
    /// Quick file download with minimal settings
    public func quickDownload(
        from urlString: String,
        to destinationPath: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> BIDownloadTask? {
        
        guard let url = URL(string: urlString) else {
            completion(.failure(BIDownloadError.invalidURL()))
            return nil
        }
        
        let task = download(url: url, destinationPath: destinationPath)
        
        // Create simple delegate for completion block
        let delegate = QuickDownloadDelegate(completion: completion)
        task.delegate = delegate
        
        // Save delegate reference in associated object
        objc_setAssociatedObject(task, &AssociatedKeys.quickDelegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        return task
    }
}

// MARK: - Quick Download Delegate

private class QuickDownloadDelegate: NSObject, BIDownloadDelegate {
    
    private let completion: (Result<String, Error>) -> Void
    
    init(completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
    }
    
    func downloadDidStart(_ task: BIDownloadTask) {
        // Do nothing
    }
    
    func downloadDidProgress(_ task: BIDownloadTask, progress: Double) {
        // Do nothing
    }
    
    func downloadDidComplete(_ task: BIDownloadTask, filePath: String) {
        completion(.success(filePath))
    }
    
    func downloadDidFail(_ task: BIDownloadTask, error: Error) {
        completion(.failure(error))
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var quickDelegate = "quickDelegate"
    static var objcQuickDelegate = "objcQuickDelegate"
}

// MARK: - Framework Initialization

/// Framework initialization (called automatically on first use)
internal class BICurlDownloaderFramework {
    
    static let shared = BICurlDownloaderFramework()
    
    private init() {
        initializeFramework()
    }
    
    private func initializeFramework() {
        let logger = BILogger.shared
        logger.info("Initializing \(BICurlDownloaderInfo.fullVersion)")
        logger.info("Supported features: \(BICurlDownloaderInfo.supportedFeatures.joined(separator: ", "))")
        
        // Check background audio capability
        checkBackgroundCapability()
        
        // Initialize cURL globally
        curl_global_init(Int(CURL_GLOBAL_DEFAULT))
        
        // Register cleanup on application termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        logger.info("Framework initialized successfully")
    }
    
    private func checkBackgroundCapability() {
        let logger = BILogger.shared
        
        logger.info("")
        logger.info("========================================")
        logger.info("BACKGROUND CAPABILITY CHECK")
        logger.info("========================================")
        
        // Check UIBackgroundModes
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            logger.info("✅ UIBackgroundModes found: \(backgroundModes.joined(separator: ", "))")
            
            if backgroundModes.contains("audio") {
                logger.info("✅ Background audio mode: ENABLED")
                logger.info("   Framework can continue downloads in background")
            } else {
                logger.warning("⚠️ Background audio mode: DISABLED")
                logger.warning("   Downloads will pause when app enters background")
                logger.warning("   ")
                logger.warning("   To enable background downloads:")
                logger.warning("   1. Open Xcode project")
                logger.warning("   2. Select app target")
                logger.warning("   3. Go to 'Signing & Capabilities' tab")
                logger.warning("   4. Click '+ Capability' button")
                logger.warning("   5. Add 'Background Modes'")
                logger.warning("   6. Enable 'Audio, AirPlay, and Picture in Picture'")
            }
        } else {
            logger.warning("⚠️ UIBackgroundModes: NOT CONFIGURED")
            logger.warning("   Downloads will pause when app enters background")
            logger.warning("   ")
            logger.warning("   To enable background downloads:")
            logger.warning("   1. Open Xcode project")
            logger.warning("   2. Select app target")
            logger.warning("   3. Go to 'Signing & Capabilities' tab")
            logger.warning("   4. Click '+ Capability' button")
            logger.warning("   5. Add 'Background Modes'")
            logger.warning("   6. Enable 'Audio, AirPlay, and Picture in Picture'")
        }
        
        // Check iOS version
        let version = UIDevice.current.systemVersion
        logger.info("ℹ️ iOS Version: \(version)")
        
        if #available(iOS 13.0, *) {
            logger.info("✅ iOS version supports all framework features")
        } else {
            logger.warning("⚠️ iOS version may have limited support")
        }
        
        logger.info("========================================")
        logger.info("")
    }
    
    @objc private func applicationWillTerminate() {
        let logger = BILogger.shared
        logger.info("Cleaning up framework resources")
        
        // Cleanup cURL resources
        curl_global_cleanup()
        
        // Cancel all downloads
        BIDownloadManager.shared.cancelAll()
        
        logger.info("Framework cleanup completed")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Framework Auto-initialization

/// Automatic framework initialization on first manager access
extension BIDownloadManager {
    
    private static let frameworkInitialization: Void = {
        _ = BICurlDownloaderFramework.shared
    }()
    
    internal static func ensureFrameworkInitialized() {
        _ = frameworkInitialization
    }
}
