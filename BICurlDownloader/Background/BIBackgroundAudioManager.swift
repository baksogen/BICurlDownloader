//
//  BIBackgroundAudioManager.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import AVFoundation
import UIKit

/// Manager for handling background audio
class BIBackgroundAudioManager: NSObject {
    
    // MARK: - Properties
    
    private var isActive = false
    private var audioEngine: AVAudioEngine?
    private var silentAudioGenerator: BISilentAudioGenerator?
    private var audioSessionCoordinator: BIAudioSessionCoordinator?
    
    private let logger = BILogger.shared
    private let stateLock = NSLock()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupComponents()
        setupNotifications()
    }
    
    deinit {
        stopBackgroundAudio()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Check if background audio capability is available
    func checkBackgroundAudioCapability() -> (available: Bool, reason: String?) {
        // Проверка 1: Background Modes в Info.plist
        guard let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            let reason = "UIBackgroundModes not found in Info.plist"
            logger.warning("⚠️ Background audio check failed: \(reason)")
            return (false, reason)
        }
        
        let hasAudioMode = backgroundModes.contains("audio")
        if !hasAudioMode {
            let reason = "'audio' mode not enabled in UIBackgroundModes (Info.plist)"
            logger.warning("⚠️ Background audio check failed: \(reason)")
            logger.warning("   Available modes: \(backgroundModes.joined(separator: ", "))")
            return (false, reason)
        }
        
        // Проверка 2: Audio Session Category
        let audioSession = AVAudioSession.sharedInstance()
        let currentCategory = audioSession.category
        
        let supportedCategories: [AVAudioSession.Category] = [
            .playback,
            .playAndRecord,
            .multiRoute
        ]
        
        if !supportedCategories.contains(currentCategory) {
            logger.info("ℹ️ Current audio category '\(currentCategory.rawValue)' will be changed to support background audio")
        }
        
        // Проверка 3: Availability для iOS версии
        if #available(iOS 13.0, *) {
            logger.info("✅ Background audio capability: AVAILABLE")
            logger.info("   - UIBackgroundModes: audio ✓")
            logger.info("   - iOS Version: \(UIDevice.current.systemVersion) ✓")
            logger.info("   - Current audio category: \(currentCategory.rawValue)")
            return (true, nil)
        } else {
            let reason = "iOS version \(UIDevice.current.systemVersion) does not support required features"
            logger.warning("⚠️ Background audio check failed: \(reason)")
            return (false, reason)
        }
    }
    
    /// Start background audio
    func startBackgroundAudio() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard !isActive else {
            logger.info("Background audio already active")
            return
        }
        
        // Проверяем доступность фонового аудио
        let capability = checkBackgroundAudioCapability()
        
        if !capability.available {
            logger.warning("⚠️ Background audio is NOT available")
            if let reason = capability.reason {
                logger.warning("   Reason: \(reason)")
            }
            logger.warning("   Framework will continue to work, but downloads may pause in background")
            logger.warning("   To enable background downloads:")
            logger.warning("   1. Open your Xcode project")
            logger.warning("   2. Select your app target")
            logger.warning("   3. Go to 'Signing & Capabilities'")
            logger.warning("   4. Add 'Background Modes' capability")
            logger.warning("   5. Enable 'Audio, AirPlay, and Picture in Picture'")
            
            // Не активируем фоновое аудио, но продолжаем работу
            isActive = false
            return
        }
        
        logger.info("Starting background audio for downloads")
        
        do {
            // Configure audio session
            try audioSessionCoordinator?.configureForBackgroundDownload()
            
            // Start silent audio generator
            try silentAudioGenerator?.start()
            
            isActive = true
            logger.info("Background audio started successfully")
            
        } catch {
            logger.error("Failed to start background audio: \(error)")
            isActive = false
        }
    }
    
    /// Stop background audio
    func stopBackgroundAudio() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard isActive else {
            logger.info("Background audio already inactive")
            return
        }
        
        logger.info("Stopping background audio")
        
        // Stop generator
        silentAudioGenerator?.stop()
        
        // Restore audio session
        audioSessionCoordinator?.restoreAudioSession()
        
        isActive = false
        logger.info("Background audio stopped")
    }
    
    /// Check if background audio is active
    var isBackgroundAudioActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isActive
    }
    
    // MARK: - Private Methods
    
    private func setupComponents() {
        audioEngine = AVAudioEngine()
        silentAudioGenerator = BISilentAudioGenerator(audioEngine: audioEngine)
        audioSessionCoordinator = BIAudioSessionCoordinator()
        
        // Set delegates
        audioSessionCoordinator?.delegate = self
    }
    
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
            selector: #selector(handleApplicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        logger.info("Audio session interruption: \(type == .began ? "began" : "ended")")
        
        switch type {
        case .began:
            // Interruption began - pause background audio
            handleInterruptionBegan()
            
        case .ended:
            // Interruption ended - resume if needed
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                handleInterruptionEnded(options: options)
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
        
        // Restart may be needed for some route changes
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            if isActive {
                restartBackgroundAudioIfNeeded()
            }
        default:
            break
        }
    }
    
    @objc private func handleApplicationWillEnterForeground() {
        logger.info("App entering foreground")
        // Background audio can remain active when returning to foreground if downloads continue
    }
    
    @objc private func handleApplicationDidEnterBackground() {
        logger.info("App entering background")
        // Ensure background audio is active if there are downloads
    }
    
    private func handleInterruptionBegan() {
        if isActive {
            logger.info("Pausing background audio due to interruption")
            silentAudioGenerator?.pause()
        }
    }
    
    private func handleInterruptionEnded(options: AVAudioSession.InterruptionOptions) {
        if isActive && options.contains(.shouldResume) {
            logger.info("Resuming background audio after interruption")
            do {
                try silentAudioGenerator?.resume()
            } catch {
                logger.error("Failed to resume background audio: \(error)")
                // Try to fully restart
                restartBackgroundAudioIfNeeded()
            }
        }
    }
    
    private func restartBackgroundAudioIfNeeded() {
        guard isActive else { return }
        
        logger.info("Restarting background audio")
        
        // Stop current audio
        silentAudioGenerator?.stop()
        
        // Give a small delay for cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.silentAudioGenerator?.start()
                self.logger.info("Background audio restarted successfully")
            } catch {
                self.logger.error("Failed to restart background audio: \(error)")
                // If restart failed, deactivate
                self.stateLock.lock()
                self.isActive = false
                self.stateLock.unlock()
            }
        }
    }
}

// MARK: - BIAudioSessionCoordinatorDelegate

extension BIBackgroundAudioManager: BIAudioSessionCoordinatorDelegate {
    
    func audioSessionCoordinatorDidDetectConflict(_ coordinator: BIAudioSessionCoordinator) {
        logger.warning("Audio session conflict detected")
        
        // Temporarily pause background audio on conflict
        if isActive {
            silentAudioGenerator?.pause()
            
            // Try to resume after a short time
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let self = self, self.isActive {
                    try? self.silentAudioGenerator?.resume()
                }
            }
        }
    }
    
    func audioSessionCoordinatorDidResolveConflict(_ coordinator: BIAudioSessionCoordinator) {
        logger.info("Audio session conflict resolved")
        
        // Resume background audio if it was active
        if isActive {
            try? silentAudioGenerator?.resume()
        }
    }
}
