//
//  RTAVisualizerView.swift
//  VoiceInk
//
//  Real-Time Analyzer frequency spectrum visualization component
//

import SwiftUI

/// Real-Time Analyzer visualization showing frequency spectrum
struct RTAVisualizerView: View {
    @ObservedObject var frequencyAnalyzer: FrequencyAnalyzer
    let color: Color
    let isActive: Bool

    // Display configuration - 21 bands for 1/3 octave (80 Hz - 8000 Hz)
    private let barCount: Int = 21
    private let barWidth: CGFloat = 5.0  // Slightly wider bars for better visual balance with fewer bars
    private let barSpacing: CGFloat = 1.5
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 64

    // Animation state
    @State private var barHeights: [CGFloat]
    @State private var barColors: [Color]
    @State private var previousHeights: [CGFloat]

    init(frequencyAnalyzer: FrequencyAnalyzer, color: Color, isActive: Bool) {
        self.frequencyAnalyzer = frequencyAnalyzer
        self.color = color
        self.isActive = isActive

        // Initialize arrays for 21 bands (1/3 octave)
        _barHeights = State(initialValue: Array(repeating: 2, count: 21))
        _barColors = State(initialValue: Array(repeating: color.opacity(0.6), count: 21))
        _previousHeights = State(initialValue: Array(repeating: 2, count: 21))
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RTABar(
                    height: barHeights[index],
                    color: barColors[index],
                    cornerRadius: 1.5
                )
                .frame(width: barWidth)
            }
        }
        .onChange(of: frequencyAnalyzer.frequencyBands) { _, newBands in
            if isActive {
                updateBars(with: newBands)
            } else {
                resetBars()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                resetBars()
            }
        }
        .onAppear {
            // Initialize with current values
            if isActive {
                updateBars(with: frequencyAnalyzer.frequencyBands)
            }
        }
    }

    private func updateBars(with frequencyData: [Float]) {
        guard frequencyData.count >= barCount else {
            return
        }

        var newHeights: [CGFloat] = []
        var newColors: [Color] = []

        for i in 0..<barCount {
            let dbValue = frequencyData[i]

            // Convert dB to height (assuming -60dB to 0dB range)
            let normalized = (dbValue + 60) / 60  // 0 to 1 range
            let targetHeight = minHeight + CGFloat(normalized) * (maxHeight - minHeight)

            // Apply attack/decay smoothing
            let isAttacking = targetHeight > previousHeights[i]
            let smoothingFactor: CGFloat = isAttacking ? 0.15 : 0.35  // Fast attack, smooth decay

            let smoothedHeight = previousHeights[i] * (1 - smoothingFactor) + targetHeight * smoothingFactor
            newHeights.append(max(minHeight, min(maxHeight, smoothedHeight)))

            // Calculate color based on magnitude
            let barColor = colorForMagnitude(normalized)
            newColors.append(barColor)
        }

        // Update previous heights for next frame
        previousHeights = newHeights

        // Animate the changes with snappier response
        withAnimation(.spring(response: 0.12, dampingFraction: 0.75)) {
            barHeights = newHeights
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            barColors = newColors
        }
    }

    private func colorForMagnitude(_ normalized: Float) -> Color {
        // Create gradient from green -> yellow -> red based on intensity
        let intensity = Double(normalized)

        if intensity < 0.33 {
            // Green to yellow-green
            return Color(
                hue: 0.33 - intensity * 0.2,  // 120° (green) to 80° (yellow-green)
                saturation: 0.7,
                brightness: 0.6 + intensity * 0.4
            )
        } else if intensity < 0.66 {
            // Yellow-green to yellow-orange
            return Color(
                hue: 0.13 - (intensity - 0.33) * 0.1,  // 80° to 40° (orange)
                saturation: 0.8,
                brightness: 0.8 + intensity * 0.2
            )
        } else {
            // Orange to red
            return Color(
                hue: 0.03 - (intensity - 0.66) * 0.03,  // 40° to 0° (red)
                saturation: 0.9,
                brightness: 0.9 + intensity * 0.1
            )
        }
    }

    private func resetBars() {
        withAnimation(.easeOut(duration: 0.2)) {
            barHeights = Array(repeating: minHeight, count: barCount)
            barColors = Array(repeating: color.opacity(0.6), count: barCount)
            previousHeights = Array(repeating: minHeight, count: barCount)
        }
    }
}

/// Individual bar in the RTA visualization
struct RTABar: View {
    let height: CGFloat
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(color)
                .frame(height: height)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Static RTA visualization when not recording
struct StaticRTAVisualizer: View {
    private let barCount: Int = 21  // 1/3 octave bands
    private let barWidth: CGFloat = 5.0  // Matching active visualizer
    private let barSpacing: CGFloat = 1.5
    private let staticHeight: CGFloat = 2.0
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.3))
                    .frame(width: barWidth, height: staticHeight)
            }
        }
    }
}

/// Preview helper for development
struct RTAVisualizerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Active RTA
            RTAVisualizerView(
                frequencyAnalyzer: FrequencyAnalyzer(),
                color: .white,
                isActive: true
            )
            .frame(height: 40)
            .padding()
            .background(Color.black)

            // Static RTA
            StaticRTAVisualizer(color: .white)
                .frame(height: 40)
                .padding()
                .background(Color.black)
        }
    }
}