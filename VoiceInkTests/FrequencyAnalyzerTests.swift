//
//  FrequencyAnalyzerTests.swift
//  VoiceInkTests
//
//  Unit tests for FrequencyAnalyzer FFT processing
//

import Testing
import AVFoundation
@testable import VoiceInk

struct FrequencyAnalyzerTests {

    // MARK: - Test Initialization

    @Test func testFrequencyAnalyzerInitialization() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()

            // Check initial state (21 bands for 1/3 octave)
            #expect(analyzer.frequencyBands.count == 21)
            #expect(analyzer.isProcessing == false)

            // Check all bands are initialized to minimum value
            for band in analyzer.frequencyBands {
                #expect(band == -60.0)
            }
        }
    }

    // MARK: - Test Frequency Mapping

    @Test func testFrequencyForBandMapping() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()

            // Test first band (80 Hz - speech lower bound)
            let firstFreq = analyzer.frequencyForBand(0)
            #expect(firstFreq == 80.0)

            // Test last band (8000 Hz - speech upper bound)
            let lastFreq = analyzer.frequencyForBand(20)
            #expect(lastFreq == 8000.0)

            // Test middle band (1000 Hz)
            let midFreq = analyzer.frequencyForBand(11)
            #expect(midFreq == 1000.0)

            // Test 1/3 octave band distribution
            // Verify some key center frequencies from ISO standard
            #expect(analyzer.frequencyForBand(1) == 100.0)
            #expect(analyzer.frequencyForBand(2) == 125.0)
            #expect(analyzer.frequencyForBand(6) == 315.0)
            #expect(analyzer.frequencyForBand(8) == 500.0)
            #expect(analyzer.frequencyForBand(14) == 2000.0)
            #expect(analyzer.frequencyForBand(18) == 5000.0)
        }
    }

    // MARK: - Test Reset Functionality

    @Test func testReset() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()

            // Simulate some processing (this would normally be done via processAudioBuffer)
            analyzer.reset()

            // Check reset state
            #expect(analyzer.isProcessing == false)
            #expect(analyzer.frequencyBands.count == 21)

            for band in analyzer.frequencyBands {
                #expect(band == -60.0)
            }
        }
    }

    // MARK: - Test Sample Processing

    @Test func testProcessSamples() async throws {
        let analyzer = await MainActor.run { FrequencyAnalyzer() }

        // Create a test sine wave at 440 Hz (A4 note)
        let sampleRate: Float = 44100.0
        let frequency: Float = 440.0
        let duration: Float = 0.1  // 100ms
        let sampleCount = Int(sampleRate * duration)

        var samples: [Float] = []
        for i in 0..<sampleCount {
            let time = Float(i) / sampleRate
            let sample = sin(2.0 * Float.pi * frequency * time)
            samples.append(sample)
        }

        // Process the samples
        await MainActor.run {
            analyzer.processSamples(samples, sampleRate: sampleRate)
        }

        // Wait for processing to complete
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // The frequency bands should show energy around 440 Hz
        // 440 Hz should be in roughly band 7-9 (logarithmic scale)
        // We can't test exact values due to FFT processing, but we can check relative magnitudes
        let bandsWithEnergy = await MainActor.run { analyzer.frequencyBands.enumerated().filter { $0.element > -40.0 } }
        #expect(!bandsWithEnergy.isEmpty, "Should detect energy in frequency bands")
    }

    // MARK: - Test Audio Buffer Processing

    @Test func testProcessAudioBuffer() async throws {
        let analyzer = await MainActor.run { FrequencyAnalyzer() }

        // Create a test audio buffer
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 44100.0,
            channels: 1
        )!

        let frameCount: AVAudioFrameCount = 1024
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            Issue.record("Failed to create audio buffer")
            return
        }

        buffer.frameLength = frameCount

        // Fill buffer with test data (white noise)
        if let channelData = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                channelData[0][i] = Float.random(in: -1.0...1.0) * 0.1
            }
        }

        // Process the buffer
        await MainActor.run {
            analyzer.processAudioBuffer(buffer)
        }

        // Wait for processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // White noise should show energy across all bands
        let bandsWithEnergy = await MainActor.run { analyzer.frequencyBands.filter { $0 > -50.0 } }
        #expect(bandsWithEnergy.count > 10, "White noise should show energy in multiple bands")
    }

    // MARK: - Performance Tests

    @Test func testProcessingPerformance() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()
            let sampleRate: Float = 44100.0
            let samples = [Float](repeating: 0.0, count: 1024)

            let startTime = Date()
            let iterations = 100

            for _ in 0..<iterations {
                analyzer.processSamples(samples, sampleRate: sampleRate)
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let averageTime = elapsed / Double(iterations)

            // Processing should be fast enough for real-time (< 30ms per buffer)
            #expect(averageTime < 0.03, "FFT processing should be fast enough for real-time")

            print("Average processing time: \(averageTime * 1000)ms")
        }
    }

    // MARK: - Edge Cases

    @Test func testEmptySamples() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()
            let emptySamples: [Float] = []

            // Should handle empty samples gracefully
            analyzer.processSamples(emptySamples, sampleRate: 44100.0)

            // Should remain in initial state
            #expect(analyzer.frequencyBands.count == 21)
            for band in analyzer.frequencyBands {
                #expect(band == -60.0)
            }
        }
    }

    @Test func testInsufficientSamples() async throws {
        await MainActor.run {
            let analyzer = FrequencyAnalyzer()
            let shortSamples = [Float](repeating: 0.0, count: 100)  // Less than required 1024

            // Should handle insufficient samples gracefully
            analyzer.processSamples(shortSamples, sampleRate: 44100.0)

            // Should remain in initial state
            #expect(analyzer.frequencyBands.count == 21)
        }
    }

    // MARK: - Test Tone Generator Helper

    private func generateTone(frequency: Float, sampleRate: Float, duration: Float) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        var samples: [Float] = []

        for i in 0..<sampleCount {
            let time = Float(i) / sampleRate
            let sample = sin(2.0 * Float.pi * frequency * time)
            samples.append(sample)
        }

        return samples
    }

    @Test func testSpecificFrequencyDetection() async throws {
        let analyzer = await MainActor.run { FrequencyAnalyzer() }

        // Test with 1kHz tone
        let testFrequency: Float = 1000.0
        let sampleRate: Float = 44100.0
        let samples = generateTone(
            frequency: testFrequency,
            sampleRate: sampleRate,
            duration: 0.1
        )

        await MainActor.run {
            analyzer.processSamples(samples, sampleRate: sampleRate)
        }

        // Wait for processing
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Find the band that should contain 1kHz (should be band 11 for 1000 Hz)
        let (expectedBand, energy) = await MainActor.run {
            var expectedBand = 0
            for i in 0..<21 {
                let freq = analyzer.frequencyForBand(i)
                if freq >= testFrequency {
                    expectedBand = i
                    break
                }
            }
            let energy = analyzer.frequencyBands[expectedBand]
            return (expectedBand, energy)
        }

        // The expected band and adjacent bands should have higher energy
        #expect(energy > -40.0, "Should detect energy at 1kHz")

        print("1kHz tone detected at band \(expectedBand) with energy: \(energy) dB")
    }
}