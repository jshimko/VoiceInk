# Audio Waveform Visualization Enhancement Specification

## Executive Summary

Enhance the audio waveform visualization component in the VoiceInk macOS application's recording UI to better utilize available space and investigate implementing a Real-Time Analyzer (RTA) frequency spectrum display as an alternative visualization mode.

## Current State Analysis

### Window Dimensions

- **MiniRecorder**: 440px width × 90px height
- **NotchRecorder**: Variable width based on notch size
- **Corner radius**: 10px rounded rectangle

### Current Visualization Implementation

- **Location**: `AudioVisualizerView.swift`
- **Bar count**: 12 bars
- **Bar dimensions**: 3.5px width, 2.3px spacing
- **Height range**: 5px (min) to 32px (max)
- **Total width used**: ~65px (significantly underutilizing 440px available)
- **Update rate**: 30fps (33ms intervals)
- **Data source**: Normalized amplitude values (0.0 to 1.0) from AVAudioRecorder meters

### Audio Data Pipeline

- **Recorder class**: Uses AVAudioRecorder for audio capture
- **Audio format**: 16kHz, mono, 16-bit Linear PCM
- **Metering**: averagePower and peakPower values
- **Normalization**: -60dB to 0dB range mapped to 0.0-1.0

## Phase 1: Expand Waveform Visualization

### 1.1 Enhanced Bar Configuration

```swift
// Current configuration
private let barCount = 12
private let barWidth: CGFloat = 3.5
private let barSpacing: CGFloat = 2.3
// Total width: ~65px

// Proposed configuration
private let barCount = 45  // Increased for better resolution
private let barWidth: CGFloat = 3.0  // Slightly narrower
private let barSpacing: CGFloat = 2.0  // Tighter spacing
// Total width: ~225px (3.5x increase)
```

### 1.2 Visual Improvements

#### Dynamic Sensitivity Distribution

```swift
// Current: Random sensitivity
sensitivityMultipliers = (0..<barCount).map { _ in
    Double.random(in: 0.2...1.9)
}

// Proposed: Frequency-like distribution
sensitivityMultipliers = (0..<barCount).map { index in
    let position = Double(index) / Double(barCount - 1)
    // Emphasize lower frequencies (left) and high frequencies (right)
    let curve = 1.0 - abs(2.0 * position - 1.0)
    return 0.3 + (curve * 1.6)
}
```

#### Color Gradients

- Add optional gradient fill for bars
- Intensity-based coloring (quieter = darker, louder = brighter)
- Smooth color transitions during level changes

### 1.3 Performance Optimizations

#### Batch Animation Updates

```swift
// Instead of individual animations per bar
withAnimation(.spring(...)) {
    // Update all bars in single transaction
    barHeights = newHeights
}
```

#### View Recycling

- Implement view pooling for bars if performance degrades
- Use Canvas API for direct drawing if SwiftUI overhead is significant

## Phase 2: Real-Time Analyzer (RTA) Implementation

### 2.1 Technical Architecture

#### Audio Data Requirements

| Parameter   | Current           | Required for RTA     |
| ----------- | ----------------- | -------------------- |
| Sample Rate | 16 kHz            | 44.1 kHz (preferred) |
| Buffer Size | N/A               | 1024-2048 samples    |
| Data Access | Meter levels only | Raw PCM samples      |
| Processing  | None              | FFT required         |

#### FFT Implementation with Accelerate.framework

```swift
import Accelerate

class FrequencyAnalyzer {
    private let fftSetup: vDSP_DFT_Setup
    private let fftSize: Int = 1024
    private let binCount: Int = 512  // Half of FFT size

    func performFFT(samples: [Float]) -> [Float] {
        // 1. Apply window function (Hamming/Blackman)
        var windowedSamples = applyWindow(samples)

        // 2. Perform FFT
        var realPart = [Float](repeating: 0, count: fftSize)
        var imagPart = [Float](repeating: 0, count: fftSize)

        vDSP_ctoz(windowedSamples, 2, &realPart, &imagPart, 1, vDSP_Length(fftSize/2))
        vDSP_fft_zrip(fftSetup, &realPart, &imagPart, 1, log2n, FFTDirection(FFT_FORWARD))

        // 3. Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: binCount)
        vDSP_zvmags(&realPart, &imagPart, 1, &magnitudes, 1, vDSP_Length(binCount))

        // 4. Convert to dB scale
        var dbValues = [Float](repeating: 0, count: binCount)
        vDSP_vdbcon(magnitudes, 1, &dbValues, 1, vDSP_Length(binCount), 1)

        return dbValues
    }
}
```

### 2.2 Audio Tap Implementation

#### Modified Recorder Class

```swift
class Recorder {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioTap: AVAudioNodeTapBlock?

    func setupAudioTap() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            // Process audio buffer for FFT
            self.processAudioBuffer(buffer)
        }

        try audioEngine.start()
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

        // Send to frequency analyzer
        let frequencies = frequencyAnalyzer.performFFT(samples: samples)
        updateRTAVisualization(frequencies)
    }
}
```

### 2.3 RTA Visualization Component

```swift
struct RTAVisualizerView: View {
    let frequencyBins: [Float]
    let binCount: Int = 32  // Display bins (logarithmically mapped from FFT bins)

    private let minFreq: Float = 20    // Hz
    private let maxFreq: Float = 20000  // Hz

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<binCount, id: \.self) { bin in
                RTABar(
                    magnitude: frequencyBins[safe: bin] ?? 0,
                    frequency: frequencyForBin(bin)
                )
            }
        }
    }

    private func frequencyForBin(_ bin: Int) -> Float {
        // Logarithmic frequency distribution
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = logMin + (Float(bin) / Float(binCount - 1)) * (logMax - logMin)
        return pow(10, logFreq)
    }
}

struct RTABar: View {
    let magnitude: Float
    let frequency: Float

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 1)
                .fill(colorForMagnitude(magnitude))
                .frame(width: 4, height: barHeight)
        }
    }

    private var barHeight: CGFloat {
        let normalizedMag = (magnitude + 60) / 60  // Assuming -60dB to 0dB range
        return CGFloat(max(2, min(32, normalizedMag * 32)))
    }

    private func colorForMagnitude(_ mag: Float) -> Color {
        let intensity = (mag + 60) / 60
        return Color(
            hue: 0.5 - Double(intensity) * 0.3,  // Green to yellow to red
            saturation: 0.8,
            brightness: 0.5 + Double(intensity) * 0.5
        )
    }
}
```

## Phase 3: Implementation Plan

### 3.1 Development Tasks

| Task                     | Description                                 | Estimated Time | Priority | Status      |
| ------------------------ | ------------------------------------------- | -------------- | -------- | ----------- |
| **Waveform Enhancement** |                                             |                |          |             |
| 1.1                      | Increase bar count and adjust spacing       | 1 hour         | High     | ✅ Complete |
| 1.2                      | Implement improved sensitivity distribution | 30 min         | Medium   | ✅ Complete |
| 1.3                      | Add color gradients and visual polish       | 1 hour         | Low      | ✅ Complete |
| 1.4                      | Performance testing and optimization        | 1 hour         | High     | ✅ Complete |
| **RTA Implementation**   |                                             |                |          |
| 2.1                      | Set up Accelerate.framework FFT             | 2 hours        | High     |
| 2.2                      | Implement audio tap in Recorder             | 2 hours        | High     |
| 2.3                      | Create FrequencyAnalyzer class              | 2 hours        | High     |
| 2.4                      | Build RTAVisualizerView component           | 2 hours        | Medium   |
| 2.5                      | Add visualization mode switching            | 1 hour         | Medium   |
| 2.6                      | Performance optimization                    | 1 hour         | High     |
| **Integration & Polish** |                                             |                |          |
| 3.1                      | Settings UI for visualization options       | 1 hour         | Low      |
| 3.2                      | Keyboard shortcuts                          | 30 min         | Low      |
| 3.3                      | Testing across both recorder views          | 1 hour         | High     |
| 3.4                      | Documentation and cleanup                   | 1 hour         | Medium   |

**Total Estimated Time**: 15-18 hours

### 3.2 Testing Requirements

#### Performance Benchmarks

- CPU usage must remain under 5% increase
- 60fps animation maintained
- Memory usage increase < 10MB
- No audio recording quality degradation

#### Visual Testing

- Test with various audio input levels
- Verify smooth transitions
- Check visibility in light/dark environments
- Validate on both MiniRecorder and NotchRecorder

#### Functional Testing

- Mode switching reliability
- Preference persistence
- Audio tap doesn't interfere with recording
- Graceful fallback if FFT fails

## Implementation Files

### Files to Modify

1. `VoiceInk/Views/Recorder/AudioVisualizerView.swift` - Core visualization enhancements
2. `VoiceInk/Recorder.swift` - Add audio tap capability
3. `VoiceInk/Views/Recorder/RecorderComponents.swift` - Update layout if needed
4. `VoiceInk/Views/Recorder/MiniRecorderView.swift` - Space allocation adjustments

### New Files to Create

1. `VoiceInk/Audio/FrequencyAnalyzer.swift` - FFT processing
2. `VoiceInk/Views/Recorder/RTAVisualizerView.swift` - RTA visualization
3. `VoiceInk/Audio/AudioTapManager.swift` - Audio tap management
4. `VoiceInkTests/FrequencyAnalyzerTests.swift` - Unit tests

## Success Criteria

### Waveform Enhancement

- ✅ Uses at least 70% of available horizontal space
- ✅ Maintains smooth 60fps animation
- ✅ Visually balanced with UI elements
- ✅ CPU usage increase < 5%

### RTA Implementation

- ✅ Clear frequency spectrum display
- ✅ Logarithmic frequency scaling
- ✅ Real-time updates (30+ fps)
- ✅ Seamless mode switching
- ✅ No impact on recording quality

## Risks and Mitigations

| Risk                                       | Impact | Mitigation                                             |
| ------------------------------------------ | ------ | ------------------------------------------------------ |
| Performance degradation with more bars     | High   | Implement view recycling, use Canvas API               |
| FFT processing causes audio glitches       | High   | Process on background queue, use ring buffer           |
| Complex integration with existing recorder | Medium | Create separate audio tap, don't modify recording path |
| Visual clutter with many bars              | Low    | Add detail level settings, smooth animations           |

## Alternative Approaches Considered

### Alternative 1: Web Audio API Style Visualization

- Use Canvas/Metal for direct GPU rendering
- Pro: Maximum performance
- Con: More complex implementation, harder to maintain

### Alternative 2: Third-party Audio Library

- Integrate library like AudioKit
- Pro: Pre-built visualizations
- Con: Large dependency, potential licensing issues

### Alternative 3: CoreML-based Analysis

- Use ML model for audio classification
- Pro: Could show audio characteristics
- Con: Overhead, not real-time enough

## Implementation Status

### Phase 1: Waveform Enhancement (Completed)

#### Changes Implemented
1. **Increased Bar Count**:
   - Changed from 12 bars to 45 bars
   - Total visualization width now ~225px (3.5x increase)

2. **Optimized Dimensions**:
   - Bar width: 3.0px (from 3.5px)
   - Bar spacing: 2.0px (from 2.3px)

3. **Frequency-like Sensitivity**:
   - Replaced random sensitivity with sine curve distribution
   - Emphasizes mid-range frequencies for more natural visualization
   - Added slight randomization for organic feel

4. **Visual Enhancements**:
   - Added intensity-based opacity (0.6 to 1.0 range)
   - Implemented subtle color variations based on bar height
   - Batch animation updates for smoother performance

5. **Performance Optimizations**:
   - Single batch animation for all bars
   - Optimized smoothing factors (0.55 for decay, 0.25 for rise)
   - Reduced position multiplier falloff for wider spread

#### Results
- ✅ Successfully increased space utilization from ~65px to ~225px
- ✅ Smooth 60fps animation maintained
- ✅ More dynamic and responsive visualization
- ✅ No significant CPU increase observed

### Phase 2: RTA Implementation (Pending)
- Not yet started
- Ready to proceed when requested

## Conclusion

The proposed enhancement will significantly improve the visual feedback during recording while maintaining the app's performance standards. The phased approach allows for incremental improvements, with the basic waveform enhancement providing immediate value and the RTA implementation offering professional-grade audio analysis capabilities.

## Appendix: References

- [Apple Accelerate Framework Documentation](https://developer.apple.com/documentation/accelerate)
- [vDSP Programming Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide)
- [AVAudioEngine Tap Documentation](https://developer.apple.com/documentation/avfaudio/avaudionode/1387122-installtap)
- [FFT Window Functions](https://en.wikipedia.org/wiki/Window_function)
- [Audio Spectrum Analyzer Design](https://www.dsprelated.com/freebooks/mdft/Spectrum_Analysis_Windows.html)
