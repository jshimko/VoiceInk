import SwiftUI

struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    private let barCount: Int = 45
    private let minHeight: CGFloat = 5
    private let maxHeight: CGFloat = 32
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 2.0
    private let hardThreshold: Double = 0.3

    private let sensitivityMultipliers: [Double]

    @State private var barHeights: [CGFloat]
    @State private var targetHeights: [CGFloat]

    init(audioMeter: AudioMeter, color: Color, isActive: Bool) {
        self.audioMeter = audioMeter
        self.color = color
        self.isActive = isActive

        let count: Int = 45

        // Create frequency-like distribution for more realistic visualization
        self.sensitivityMultipliers = (0..<count).map { index in
            let position: Double = Double(index) / Double(count - 1)
            // Create a curve that emphasizes lower and mid frequencies
            let curve: Double = sin(position * .pi) * 0.7 + 0.3
            // Add slight randomization for organic feel
            let randomVariation: Double = Double.random(in: 0.9...1.1)
            return curve * randomVariation * 1.8
        }

        _barHeights = State(initialValue: Array(repeating: minHeight, count: count))
        _targetHeights = State(initialValue: Array(repeating: minHeight, count: count))
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.7)
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeights[index])
                    .opacity(barOpacity(for: index))
            }
        }
        .onChange(of: audioMeter) { _, newValue in
            if isActive {
                updateBars(with: Float(newValue.averagePower))
            } else {
                resetBars()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                resetBars()
            }
        }
    }

    // Add intensity-based coloring
    private func barColor(for index: Int) -> Color {
        let heightRatio: CGFloat = (barHeights[index] - minHeight) / (maxHeight - minHeight)
        // Subtle color variation based on height
        if heightRatio > 0.7 {
            return color  // Full intensity
        } else if heightRatio > 0.4 {
            return color.opacity(0.95)
        } else {
            return color.opacity(0.9)
        }
    }

    // Add subtle opacity variation for depth
    private func barOpacity(for index: Int) -> Double {
        let heightRatio: CGFloat = (barHeights[index] - minHeight) / (maxHeight - minHeight)
        return 0.6 + (heightRatio * 0.4)  // Range from 0.6 to 1.0
    }

    private func updateBars(with audioLevel: Float) {
        let rawLevel: Double = max(0, min(1, Double(audioLevel)))
        let adjustedLevel: Double = rawLevel < hardThreshold ? 0 : (rawLevel - hardThreshold) / (1.0 - hardThreshold)

        let range: CGFloat = maxHeight - minHeight
        let center: Int = barCount / 2

        // Batch animation for better performance with more bars
        var newHeights: [CGFloat] = []

        for i in 0..<barCount {
            let distanceFromCenter: Int = abs(i - center)
            let positionMultiplier: Double = 1.0 - (Double(distanceFromCenter) / Double(center)) * 0.3  // Reduced falloff for wider spread

            // Use frequency-like sensitivity
            let sensitivityAdjustedLevel: Double = adjustedLevel * positionMultiplier * sensitivityMultipliers[i]

            let targetHeight: CGFloat = minHeight + CGFloat(sensitivityAdjustedLevel) * range

            let isDecaying: Bool = targetHeight < targetHeights[i]
            let smoothingFactor: CGFloat = isDecaying ? 0.55 : 0.25  // Slightly faster response

            targetHeights[i] = targetHeights[i] * (1 - smoothingFactor) + targetHeight * smoothingFactor

            newHeights.append(targetHeights[i])
        }

        // Single batch animation for all bars
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            barHeights = newHeights
        }
    }

    private func resetBars() {
        withAnimation(.easeOut(duration: 0.15)) {
            barHeights = Array(repeating: minHeight, count: barCount)
            targetHeights = Array(repeating: minHeight, count: barCount)
        }
    }
}

struct StaticVisualizer: View {
    private let barCount: Int = 45
    private let barWidth: CGFloat = 3.0
    private let staticHeight: CGFloat = 5.0
    private let barSpacing: CGFloat = 2.0
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.7)
                    .fill(color)
                    .frame(width: barWidth, height: staticHeight)
            }
        }
    }
}
