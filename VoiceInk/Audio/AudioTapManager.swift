//
//  AudioTapManager.swift
//  VoiceInk
//
//  Manages AVAudioEngine tap for capturing raw audio samples
//

import Foundation
import AVFoundation
import os

/// Protocol for receiving audio tap data
protocol AudioTapDelegate: AnyObject {
    func audioTapManager(_ manager: AudioTapManager, didReceiveBuffer buffer: AVAudioPCMBuffer)
    func audioTapManagerDidStop(_ manager: AudioTapManager)
}

/// Manages audio tap for real-time audio analysis
@MainActor
class AudioTapManager: NSObject, ObservableObject {
    // MARK: - Properties

    nonisolated private let logger = Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "AudioTapManager")

    // Audio Engine (nonisolated(unsafe) for thread-safe access)
    nonisolated(unsafe) private var audioEngine: AVAudioEngine?
    nonisolated(unsafe) private var inputNode: AVAudioInputNode?
    nonisolated(unsafe) private var isRunning = false

    // Tap configuration
    private let bufferSize: AVAudioFrameCount = 1024
    private let targetSampleRate: Double = 44100.0  // Target sample rate for better frequency resolution

    // Delegate
    weak var delegate: AudioTapDelegate?

    // Published state
    @Published var isTapping: Bool = false
    @Published var currentSampleRate: Double = 0

    // Ring buffer for sample accumulation (nonisolated for thread-safe access)
    nonisolated(unsafe) private var ringBuffer: [Float] = []
    nonisolated private let maxBufferSize = 4096
    nonisolated private let bufferQueue = DispatchQueue(label: "com.voiceink.audiotap.buffer", qos: .userInteractive)

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
    }

    deinit {
        stopTap()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode

        guard let engine = audioEngine, let input = inputNode else {
            logger.error("Failed to create audio engine or input node")
            return
        }

        logger.info("Audio engine setup completed")
    }

    // MARK: - Tap Management

    /// Start audio tap for frequency analysis
    func startTap(deviceID: AudioDeviceID? = nil) async throws {
        guard let engine = audioEngine, let input = inputNode else {
            throw AudioTapError.engineNotAvailable
        }

        // Stop existing tap if running
        if isRunning {
            stopTap()
        }

        // Configure device if specified
        if let deviceID = deviceID {
            configureInputDevice(deviceID)
        }

        // Get current input format
        let inputFormat = input.outputFormat(forBus: 0)
        currentSampleRate = inputFormat.sampleRate

        logger.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        // Create target format for analysis (44.1kHz mono)
        guard let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            throw AudioTapError.formatCreationFailed
        }

        // Create converter if needed
        let needsConversion = inputFormat.sampleRate != targetSampleRate

        // Install tap on input node
        input.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: needsConversion ? nil : targetFormat  // Use nil to get native format, convert later
        ) { [weak self] buffer, time in
            guard let self = self else { return }

            // Process buffer
            if needsConversion {
                // Convert sample rate if needed
                self.convertAndProcessBuffer(buffer, targetFormat: targetFormat)
            } else {
                self.processBuffer(buffer)
            }
        }

        // Start engine
        do {
            try engine.start()
            isRunning = true
            isTapping = true
            logger.info("Audio tap started successfully")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            throw AudioTapError.engineStartFailed(error)
        }
    }

    /// Stop audio tap
    nonisolated func stopTap() {
        guard let engine = audioEngine, let input = inputNode else { return }

        if isRunning {
            input.removeTap(onBus: 0)
            engine.stop()

            Task { @MainActor in
                self.isRunning = false
                self.isTapping = false
            }

            // Clear buffers
            bufferQueue.sync {
                ringBuffer.removeAll()
            }

            logger.info("Audio tap stopped")

            Task { @MainActor in
                self.delegate?.audioTapManagerDidStop(self)
            }
        }
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Send to delegate immediately
        delegate?.audioTapManager(self, didReceiveBuffer: buffer)

        // Also accumulate in ring buffer for analysis
        accumulateSamples(from: buffer)
    }

    private func convertAndProcessBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            logger.error("Failed to create audio converter")
            return
        }

        // Calculate output buffer size
        let outputCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            logger.error("Failed to create output buffer")
            return
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(
            to: outputBuffer,
            error: &error,
            withInputFrom: inputBlock
        )

        if status == .error {
            logger.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
        } else {
            processBuffer(outputBuffer)
        }
    }

    private func accumulateSamples(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frames = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))

        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            // Add to ring buffer
            self.ringBuffer.append(contentsOf: samples)

            // Maintain maximum size
            if self.ringBuffer.count > self.maxBufferSize {
                self.ringBuffer.removeFirst(self.ringBuffer.count - self.maxBufferSize)
            }
        }
    }

    // MARK: - Device Configuration

    private func configureInputDevice(_ deviceID: AudioDeviceID) {
        // This would integrate with AudioDeviceManager if needed
        // For now, we'll use the system default as configured by Recorder
        logger.info("Using device ID: \(deviceID)")
    }

    // MARK: - Sample Access

    /// Get current accumulated samples
    func getCurrentSamples() -> [Float] {
        return bufferQueue.sync {
            return Array(ringBuffer)
        }
    }

    /// Get latest samples of specified count
    func getLatestSamples(count: Int) -> [Float] {
        return bufferQueue.sync {
            guard ringBuffer.count >= count else {
                return Array(ringBuffer)
            }
            return Array(ringBuffer.suffix(count))
        }
    }

    // MARK: - Error Handling

    enum AudioTapError: LocalizedError {
        case engineNotAvailable
        case formatCreationFailed
        case engineStartFailed(Error)

        var errorDescription: String? {
            switch self {
            case .engineNotAvailable:
                return "Audio engine not available"
            case .formatCreationFailed:
                return "Failed to create audio format"
            case .engineStartFailed(let error):
                return "Failed to start audio engine: \(error.localizedDescription)"
            }
        }
    }
}