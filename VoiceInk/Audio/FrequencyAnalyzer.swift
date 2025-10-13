//
//  FrequencyAnalyzer.swift
//  VoiceInk
//
//  Created for RTA (Real-Time Analyzer) frequency spectrum visualization
//

import Foundation
import Accelerate
import AVFoundation
import os

/// Performs FFT analysis on audio samples to extract frequency spectrum data
@MainActor
class FrequencyAnalyzer: ObservableObject {
    // MARK: - Properties

    private let logger = Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "FrequencyAnalyzer")

    // FFT Configuration
    private let fftSize: Int = 1024
    private let log2n: vDSP_Length
    private var fftSetup: FFTSetup?

    // Frequency band configuration - 1/3 octave bands for speech (80 Hz - 8000 Hz)
    private let displayBandCount: Int = 21
    private let minFrequency: Float = 80.0     // Hz - Lower bound for speech
    private let maxFrequency: Float = 8000.0   // Hz - Upper bound for speech

    // 1/3 octave band center frequencies (ISO 61260 standard)
    private let thirdOctaveCenters: [Float] = [
        80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
        800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000
    ]

    // Processing buffers
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var frequencyBinValues: [Float]

    // Output
    @Published var frequencyBands: [Float] = []
    @Published var isProcessing: Bool = false

    // Processing queue
    private let processingQueue = DispatchQueue(label: "com.voiceink.frequencyanalyzer", qos: .userInteractive)

    // MARK: - Initialization

    init() {
        // Calculate log2 of FFT size
        self.log2n = vDSP_Length(log2(Double(fftSize)))

        // Initialize buffers
        self.window = [Float](repeating: 0, count: fftSize)
        self.realBuffer = [Float](repeating: 0, count: fftSize)
        self.imagBuffer = [Float](repeating: 0, count: fftSize)
        self.magnitudeBuffer = [Float](repeating: 0, count: fftSize/2)
        self.frequencyBinValues = [Float](repeating: 0, count: fftSize/2)

        // Initialize frequency bands array (21 bands for 1/3 octave)
        self.frequencyBands = [Float](repeating: -60.0, count: 21)

        // Setup FFT
        setupFFT()

        // Create window function
        createHammingWindow()
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    // MARK: - Setup

    private func setupFFT() {
        // Create FFT setup (reusable configuration)
        fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))

        if fftSetup == nil {
            logger.error("Failed to create FFT setup")
        } else {
            logger.info("FFT setup created successfully with size: \(self.fftSize)")
        }
    }

    private func createHammingWindow() {
        // Create Hamming window for better frequency resolution
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hamm_window(&window, vDSP_Length(fftSize), Int32(0))
        self.window = window
    }

    // MARK: - Audio Processing

    /// Process audio buffer and extract frequency spectrum
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let fftSetup = fftSetup,
              let channelData = buffer.floatChannelData else {
            logger.error("FFT setup or channel data not available")
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount >= fftSize else {
            logger.debug("Buffer too small: \(frameCount) < \(self.fftSize)")
            return
        }

        // Process on background queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Extract samples from buffer
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            // Process FFT
            let frequencies = self.performFFT(samples: samples, sampleRate: Float(buffer.format.sampleRate))

            // Update UI on main thread
            Task { @MainActor in
                self.frequencyBands = frequencies
                self.isProcessing = false
            }
        }
    }

    /// Process raw audio samples
    func processSamples(_ samples: [Float], sampleRate: Float) {
        guard samples.count >= fftSize else {
            logger.debug("Not enough samples: \(samples.count) < \(self.fftSize)")
            return
        }

        isProcessing = true

        // Process on background queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            let frequencies = self.performFFT(samples: Array(samples.prefix(self.fftSize)), sampleRate: sampleRate)

            // Update UI on main thread
            Task { @MainActor in
                self.frequencyBands = frequencies
                self.isProcessing = false
            }
        }
    }

    // MARK: - FFT Processing

    private func performFFT(samples: [Float], sampleRate: Float) -> [Float] {
        guard let fftSetup = fftSetup else {
            logger.error("FFT setup not available")
            return [Float](repeating: -60.0, count: displayBandCount)
        }

        // Apply window function
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        // Prepare complex buffer
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)

        // Copy windowed samples to real part
        real = windowedSamples

        // Create complex split and perform FFT operations
        var magnitudes = [Float](repeating: 0, count: fftSize/2)
        var dbValues = [Float](repeating: 0, count: fftSize/2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Perform forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, Int32(FFT_FORWARD))

                // Calculate magnitudes (magnitude squared)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize/2))
            }
        }

        // Normalize by FFT size (squared since we have magnitude squared)
        var fftNorm = Float(fftSize * fftSize) / 4.0  // Divide by 4 for proper scaling
        vDSP_vsdiv(magnitudes, 1, &fftNorm, &magnitudes, 1, vDSP_Length(fftSize/2))

        // Add small epsilon to avoid log(0)
        var epsilon: Float = 1e-10
        vDSP_vsadd(magnitudes, 1, &epsilon, &magnitudes, 1, vDSP_Length(fftSize/2))

        // Convert to dB using power form (10*log10) since we have magnitude squared
        var ref: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &ref, &dbValues, 1, vDSP_Length(fftSize/2), 0)

        // Clamp to reasonable range (-60dB to 0dB)
        var minDB: Float = -60.0
        var maxDB: Float = 0.0
        vDSP_vclip(dbValues, 1, &minDB, &maxDB, &dbValues, 1, vDSP_Length(fftSize/2))

        // Map to display bands (logarithmic frequency distribution)
        return mapToDisplayBands(dbValues: dbValues, sampleRate: sampleRate)
    }

    // MARK: - Frequency Mapping

    private func mapToDisplayBands(dbValues: [Float], sampleRate: Float) -> [Float] {
        var displayBands = [Float](repeating: -60.0, count: displayBandCount)

        let nyquistFreq = sampleRate / 2.0
        let binWidth = nyquistFreq / Float(fftSize/2)

        // 1/3 octave band factor (2^(1/6) for calculating band edges)
        let octaveRatio: Float = pow(2.0, 1.0/6.0)  // ≈ 1.122

        for bandIndex in 0..<displayBandCount {
            let centerFreq = thirdOctaveCenters[bandIndex]

            // Calculate 1/3 octave band edges
            let freqLow = centerFreq / octaveRatio
            let freqHigh = centerFreq * octaveRatio

            // Find corresponding FFT bins
            let binLow = Int(freqLow / binWidth)
            let binHigh = min(Int(freqHigh / binWidth), dbValues.count - 1)

            if binLow < dbValues.count && binHigh >= binLow {
                // Sum the power in this band (in dB domain, we need to convert back to linear)
                let binRange = binLow...binHigh
                let validBins = binRange.filter { $0 < dbValues.count }

                if !validBins.isEmpty {
                    // Convert from dB to linear power, sum, then convert back to dB
                    var linearSum: Float = 0
                    for bin in validBins {
                        // Convert dB to linear power (10^(dB/10))
                        let linearPower = pow(10, dbValues[bin] / 10.0)
                        linearSum += linearPower
                    }
                    // Convert sum back to dB
                    displayBands[bandIndex] = 10 * log10(linearSum)

                    // Clamp to reasonable range
                    displayBands[bandIndex] = max(-60.0, min(0.0, displayBands[bandIndex]))
                }
            }
        }

        // Apply smoothing for visual appeal
        return smoothBands(displayBands)
    }

    private func smoothBands(_ bands: [Float]) -> [Float] {
        var smoothed = bands
        let smoothingFactor: Float = 0.3

        // Apply temporal smoothing with current values
        for i in 0..<displayBandCount {
            let currentValue = frequencyBands[i]
            let newValue = bands[i]

            // Much faster attack, slower decay for responsive feel
            if newValue > currentValue {
                smoothed[i] = currentValue * (1 - smoothingFactor * 3) + newValue * (smoothingFactor * 3)  // 3x faster attack
            } else {
                smoothed[i] = currentValue * (1 - smoothingFactor) + newValue * smoothingFactor
            }
        }

        return smoothed
    }

    // MARK: - Helper Methods

    /// Get frequency for a specific display band (returns 1/3 octave center frequency)
    func frequencyForBand(_ bandIndex: Int) -> Float {
        guard bandIndex >= 0 && bandIndex < displayBandCount else { return 0 }

        return thirdOctaveCenters[bandIndex]
    }

    /// Reset frequency data
    func reset() {
        frequencyBands = [Float](repeating: -60.0, count: 21)
        isProcessing = false
    }
}