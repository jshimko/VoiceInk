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
        .clipShape(Capsule())
    }

    private var statusView: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter
        )
    }

    private var contentLayout: some View {
        VStack(spacing: 0) {
            // Main recorder controls
            HStack(spacing: 0) {
                // Left button zone - always visible
                RecorderPromptButton(activePopover: $activePopover)
                    .padding(.leading, 7)

                Spacer()

                // Fixed visualizer zone
                statusView
                    .frame(maxWidth: .infinity)

                Spacer()

                // Right button zone - always visible
                RecorderPowerModeButton(activePopover: $activePopover)
                    .padding(.trailing, 7)
            }
            .padding(.vertical, 9)

            // Settings info section (expandable)
            if showSettings {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 12)

                RecorderSettingsInfo(whisperState: whisperState, isCompact: false)
                    .padding(.bottom, 6)
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
    }

    private var recorderCapsule: some View {
        Capsule()
            .fill(.clear)
            .background(backgroundView)
            .overlay {
                Capsule()
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


