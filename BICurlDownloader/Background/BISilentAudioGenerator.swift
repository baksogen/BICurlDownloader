//
//  BISilentAudioGenerator.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import AVFoundation

/// Generator of silent audio to maintain background mode
class BISilentAudioGenerator: NSObject {
    
    // MARK: - Properties
    
    private let audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var silentBuffer: AVAudioPCMBuffer?
    private var isPlaying = false
    private var isPaused = false
    
    private let logger = BILogger.shared
    private let stateLock = NSLock()
    
    // Generator parameters
    private let sampleRate: Double = 44100.0
    private let bufferDuration: TimeInterval = 1.0 // 1 second buffer
    private let silentFrequency: Float = 20.0 // 20 Hz - almost inaudible
    private let amplitude: Float = 0.001 // Very quiet sound
    
    // MARK: - Initialization
    
    init(audioEngine: AVAudioEngine?) {
        self.audioEngine = audioEngine
        super.init()
        setupAudioComponents()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Start generating silent audio
    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard !isPlaying else {
            logger.info("Silent audio generator already playing")
            return
        }
        
        logger.info("Starting silent audio generator")
        
        // Create silent buffer if needed
        if silentBuffer == nil {
            try createSilentBuffer()
        }
        
        // Setup and start audio engine
        try setupAndStartAudioEngine()
        
        // Start playback
        startPlayback()
        
        isPlaying = true
        isPaused = false
        
        logger.info("Silent audio generator started successfully")
    }
    
    /// Stop generation
    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard isPlaying else {
            logger.info("Silent audio generator already stopped")
            return
        }
        
        logger.info("Stopping silent audio generator")
        
        // Stop playback
        playerNode?.stop()
        
        // Stop audio engine
        audioEngine?.stop()
        
        isPlaying = false
        isPaused = false
        
        logger.info("Silent audio generator stopped")
    }
    
    /// Pause generation
    func pause() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard isPlaying && !isPaused else {
            logger.info("Silent audio generator already paused or not playing")
            return
        }
        
        logger.info("Pausing silent audio generator")
        
        playerNode?.pause()
        isPaused = true
        
        logger.info("Silent audio generator paused")
    }
    
    /// Resume generation
    func resume() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard isPlaying && isPaused else {
            logger.info("Silent audio generator not paused or not playing")
            return
        }
        
        logger.info("Resuming silent audio generator")
        
        // Resume playback
        playerNode?.play()
        isPaused = false
        
        logger.info("Silent audio generator resumed")
    }
    
    /// Generator status
    var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isPlaying && !isPaused
    }
    
    // MARK: - Private Methods
    
    private func setupAudioComponents() {
        guard let engine = audioEngine else {
            logger.error("Audio engine not available")
            return
        }
        
        // Create player node
        playerNode = AVAudioPlayerNode()
        
        // Add node to engine
        if let player = playerNode {
            engine.attach(player)
            
            // Connect to main mixer node
            let mainMixer = engine.mainMixerNode
            engine.connect(player, to: mainMixer, format: nil)
        }
    }
    
    private func createSilentBuffer() throws {
        guard let engine = audioEngine else {
            let error = NSError(domain: "BISilentAudioGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio engine not available"])
            throw BIDownloadError.fileSystemError(error)
        }
        
        let format = engine.mainMixerNode.inputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            let error = NSError(domain: "BISilentAudioGenerator", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
            throw BIDownloadError.fileSystemError(error)
        }
        
        buffer.frameLength = frameCount
        
        // Fill buffer with silent sinusoidal signal
        generateSilentWaveform(buffer: buffer, format: format)
        
        silentBuffer = buffer
        logger.info("Created silent buffer with \(frameCount) frames at \(format.sampleRate) Hz")
    }
    
    private func generateSilentWaveform(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        
        for channel in 0..<channelCount {
            let channelBuffer = channelData[channel]
            
            for frame in 0..<frameCount {
                let time = Float(frame) / Float(format.sampleRate)
                let sample = amplitude * sin(2.0 * Float.pi * silentFrequency * time)
                channelBuffer[frame] = sample
            }
        }
    }
    
    private func setupAndStartAudioEngine() throws {
        guard let engine = audioEngine else {
            let error = NSError(domain: "BISilentAudioGenerator", code: -3, userInfo: [NSLocalizedDescriptionKey: "Audio engine not available"])
            throw BIDownloadError.fileSystemError(error)
        }
        
        // Prepare engine
        engine.prepare()
        
        // Start engine
        try engine.start()
        
        logger.info("Audio engine started successfully")
    }
    
    private func startPlayback() {
        guard let player = playerNode,
              let buffer = silentBuffer else {
            logger.error("Player node or buffer not available")
            return
        }
        
        // Start player node
        player.play()
        
        // Schedule cyclic buffer playback
        scheduleBufferLoop(player: player, buffer: buffer)
        
        logger.info("Started silent audio playback loop")
    }
    
    private func scheduleBufferLoop(player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        // Schedule buffer playback
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            // When buffer finishes, schedule next one
            DispatchQueue.global(qos: .background).async {
                guard let self = self else { return }
                
                self.stateLock.lock()
                let shouldContinue = self.isPlaying && !self.isPaused
                self.stateLock.unlock()
                
                if shouldContinue {
                    self.scheduleBufferLoop(player: player, buffer: buffer)
                }
            }
        })
    }
}
