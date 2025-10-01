//
//  BILogger.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import os.log

/// Logger for BICurlDownloader framework
class BILogger {
    
    // MARK: - Singleton
    
    static let shared = BILogger()
    
    // MARK: - Properties
    
    private var isEnabled = false
    private var currentLevel: BILogLevel = .info
    private let osLog = OSLog(subsystem: "com.bi.curldownloader", category: "BICurlDownloader")
    private let logQueue = DispatchQueue(label: "com.bi.curldownloader.logger", qos: .utility)
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Logger configuration
    func configure(level: BILogLevel, enabled: Bool) {
        logQueue.async { [weak self] in
            self?.currentLevel = level
            self?.isEnabled = enabled
        }
    }
    
    // MARK: - Logging Methods
    
    /// Logging with verbose level
    func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .verbose, message: message, file: file, function: function, line: line)
    }
    
    /// Logging with debug level
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    /// Logging with info level
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    /// Logging with warning level
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    /// Logging with error level
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private func log(level: BILogLevel, message: String, file: String, function: String, line: Int) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if logger is enabled and level matches
            guard self.isEnabled && level.rawValue >= self.currentLevel.rawValue else {
                return
            }
            
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            let timestamp = self.formatTimestamp(Date())
            let logMessage = "[\(timestamp)] [\(level.description)] [\(fileName):\(line)] \(function) - \(message)"
            
            // Output to console
//            print(logMessage)
            
            // Log through os_log for better system integration
            if #available(iOS 14.0, *) {
                os_log("%{public}@", log: self.osLog, type: level.osLogType, logMessage)
            } else {
                os_log("%{public}@", log: self.osLog, type: level.osLogType, logMessage)
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - BILogLevel Extensions

extension BILogLevel {
    
    /// Log level description
    var description: String {
        switch self {
        case .verbose:
            return "VERBOSE"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .none:
            return "NONE"
        }
    }
    
    /// Corresponding type for os_log
    var osLogType: OSLogType {
        switch self {
        case .verbose:
            return .debug
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .none:
            return .info
        }
    }
}
