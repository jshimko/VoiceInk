import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    @State private var activePopover: ActivePopoverState = .none
    @State private var showSettings: Bool = true

    private var backgroundView: some View {
        ZStack {
            Color.black.opacity(0.9)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.95),
                    Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.05)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusView: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter,
            recorder: recorder
        )
    }

    private var contentLayout: some View {
        VStack(spacing: 0) {
            // Main recorder controls
            HStack(spacing: 0) {
                // Left button zone - always visible
                RecorderPromptButton(activePopover: $activePopover)
                    .padding(.leading, 16)

                // Visualization mode toggle
                RecorderVisualizationButton(
                    recorder: recorder,
                    buttonSize: 20,
                    padding: EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
                )

                Spacer()

                // Fixed visualizer zone
                statusView
                    .frame(maxWidth: .infinity)

                Spacer()

                // Right button zone - always visible
                RecorderPowerModeButton(activePopover: $activePopover)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 14)

            // Settings info section (expandable)
            if showSettings {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 20)

                RecorderSettingsInfo(whisperState: whisperState, isCompact: false)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
    }

    private var recorderCapsule: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.clear)
            .background(backgroundView)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            }
            .overlay {
                contentLayout
            }
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                recorderCapsule
            }
        }
    }
}
