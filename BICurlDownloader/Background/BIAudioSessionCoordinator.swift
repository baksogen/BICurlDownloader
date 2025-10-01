//
//  BIAudioSessionCoordinator.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import AVFoundation

/// Delegate protocol for audio session coordinator
protocol BIAudioSessionCoordinatorDelegate: AnyObject {
    func audioSessionCoordinatorDidDetectConflict(_ coordinator: BIAudioSessionCoordinator)
    func audioSessionCoordinatorDidResolveConflict(_ coordinator: BIAudioSessionCoordinator)
}

/// Coordinator for managing audio sessions and avoiding conflicts
class BIAudioSessionCoordinator: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: BIAudioSessionCoordinatorDelegate?
    
    private var originalCategory: AVAudioSession.Category?
    private var originalOptions: AVAudioSession.CategoryOptions?
    private var originalMode: AVAudioSession.Mode?
    
    private var isConfiguredForBackground = false
    private let logger = BILogger.shared
    private let sessionLock = NSLock()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    deinit {
        restoreAudioSession()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Configure audio session for background download
    func configureForBackgroundDownload() throws {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard !isConfiguredForBackground else {
            logger.info("Audio session already configured for background download")
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Save current settings
        saveCurrentAudioSessionSettings(audioSession)
        
        logger.info("Configuring audio session for background download")
        
        do {
            // Set category for playback with mixing capability
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowAirPlay, .defaultToSpeaker]
            )
            
            // Activate audio session
            try audioSession.setActive(true, options: [])
            
            isConfiguredForBackground = true
            logger.info("Audio session configured successfully for background download")
            
        } catch {
            logger.error("Failed to configure audio session: \(error)")
            throw BIDownloadErrorSwift.audioSessionError(error)
        }
    }
    
    /// Restore original audio session settings
    func restoreAudioSession() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        
        guard isConfiguredForBackground else {
            logger.info("Audio session not configured for background download")
            return
        }
        
        logger.info("Restoring original audio session settings")
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Restore original settings if they were saved
            if let category = originalCategory,
               let options = originalOptions,
               let mode = originalMode {
                try audioSession.setCategory(category, mode: mode, options: options)
            }
            
            // Deactivate audio session with notification to other apps
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            isConfiguredForBackground = false
            logger.info("Audio session restored successfully")
            
        } catch {
            logger.error("Failed to restore audio session: \(error)")
        }
        
        // Clear saved settings
        clearSavedAudioSessionSettings()
    }
    
    /// Check compatibility with current audio session
    func checkAudioSessionCompatibility() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Check if we can mix with other apps
        let canMixWithOthers = audioSession.categoryOptions.contains(.mixWithOthers)
        
        // Check category
        let compatibleCategories: [AVAudioSession.Category] = [
            .playback,
            .playAndRecord,
            .multiRoute
        ]
        
        let isCategoryCompatible = compatibleCategories.contains(audioSession.category)
        
        logger.info("Audio session compatibility check: category=\(audioSession.category), canMix=\(canMixWithOthers)")
        
        return isCategoryCompatible && canMixWithOthers
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesWereReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }
    
    private func saveCurrentAudioSessionSettings(_ audioSession: AVAudioSession) {
        originalCategory = audioSession.category
        originalOptions = audioSession.categoryOptions
        originalMode = audioSession.mode
        
        let categoryString = originalCategory?.rawValue ?? "unknown"
        let modeString = originalMode?.rawValue ?? "unknown"
        logger.info("Saved audio session settings: category=\(categoryString), mode=\(modeString)")
    }
    
    private func clearSavedAudioSessionSettings() {
        originalCategory = nil
        originalOptions = nil
        originalMode = nil
    }
    
    private func detectAndHandleConflict() {
        if !checkAudioSessionCompatibility() {
            logger.warning("Audio session conflict detected")
            delegate?.audioSessionCoordinatorDidDetectConflict(self)
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        let typeString = type == .began ? "began" : "ended"
        logger.info("Audio session interruption detected: \(typeString)")
        
        switch type {
        case .began:
            // Interruption began - possible conflict
            detectAndHandleConflict()
            
        case .ended:
            // Interruption ended - check compatibility
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                
                if options.contains(.shouldResume) {
                    // Can resume - check compatibility
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self = self else { return }
                        
                        if self.checkAudioSessionCompatibility() {
                            self.delegate?.audioSessionCoordinatorDidResolveConflict(self)
                        } else {
                            self.detectAndHandleConflict()
                        }
                    }
                }
            }
            
        @unknown default:
            logger.warning("Unknown interruption type: \(typeValue)")
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        logger.info("Audio session route change: \(reason)")
        
        // Check compatibility on route change
        switch reason {
        case .newDeviceAvailable:
            logger.info("New audio device became available")
            
        case .oldDeviceUnavailable:
            logger.info("Audio device became unavailable")
            
        case .categoryChange:
            logger.info("Audio session category changed")
            detectAndHandleConflict()
            
        case .override:
            logger.info("Audio session override occurred")
            detectAndHandleConflict()
            
        default:
            break
        }
    }
    
    @objc private func handleMediaServicesWereReset(_ notification: Notification) {
        logger.warning("Media services were reset")
        
        // Need to reconfigure audio session after media services reset
        if isConfiguredForBackground {
            logger.info("Reconfiguring audio session after media services reset")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                do {
                    try self.configureForBackgroundDownload()
                    self.delegate?.audioSessionCoordinatorDidResolveConflict(self)
                } catch {
                    self.logger.error("Failed to reconfigure audio session: \(error)")
                    self.delegate?.audioSessionCoordinatorDidDetectConflict(self)
                }
            }
        }
    }
}
