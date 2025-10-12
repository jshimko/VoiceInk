import SwiftUI

// MARK: - Shared Popover State
enum ActivePopoverState {
    case none
    case enhancement
    case power
}

// MARK: - Hover Interaction Manager
class HoverInteraction: ObservableObject {
    @Published var isHovered: Bool = false

    func setHover(on: Bool) {
        if on {
            if !isHovered {
                isHovered = true
            }
        } else {
            isHovered = false
        }
    }
}

// MARK: - Generic Toggle Button Component
struct RecorderToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void
    
    init(isEnabled: Bool, icon: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.icon = icon
        self.color = color
        self.disabled = disabled
        self.action = action
    }
    
    private var isEmoji: Bool {
        return !icon.contains(".") && !icon.contains("-") && icon.unicodeScalars.contains { !$0.isASCII }
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
            }
            .foregroundColor(disabled ? .white.opacity(0.3) : (isEnabled ? .white : .white.opacity(0.6)))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Generic Record Button Component
struct RecorderRecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 25, height: 25)
                
                if isProcessing {
                    ProcessingIndicator(color: .white)
                        .frame(width: 16, height: 16)
                } else if isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
    }
    
    private var buttonColor: Color {
        if isProcessing {
            return Color(red: 0.4, green: 0.4, blue: 0.45)
        } else if isRecording {
            return .red
        } else {
            return Color(red: 0.3, green: 0.3, blue: 0.35)
        }
    }
}

// MARK: - Processing Indicator Component
struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color
    
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.7)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Progress Animation Component
struct ProgressAnimation: View {
    @State private var currentDot = 0
    @State private var timer: Timer?
    let animationSpeed: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index <= currentDot ? 0.8 : 0.2))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: animationSpeed, repeats: true) { _ in
                currentDot = (currentDot + 1) % 7
                if currentDot >= 5 { currentDot = -1 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Prompt Button Component
struct RecorderPromptButton: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Binding var activePopover: ActivePopoverState
    let buttonSize: CGFloat
    let padding: EdgeInsets
    @State private var isHoveringEnhancement: Bool = false
    @State private var isHoveringEnhancementPopover: Bool = false
    @State private var enhancementDismissWorkItem: DispatchWorkItem?

    init(activePopover: Binding<ActivePopoverState>, buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 0)) {
        self._activePopover = activePopover
        self.buttonSize = buttonSize
        self.padding = padding
    }
    
    var body: some View {
        RecorderToggleButton(
            isEnabled: enhancementService.isEnhancementEnabled,
            icon: enhancementService.activePrompt?.icon.rawValue ?? enhancementService.allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId })?.icon.rawValue ?? "checkmark.seal.fill",
            color: .blue,
            disabled: false
        ) {
            if enhancementService.isEnhancementEnabled {
                activePopover = activePopover == .enhancement ? .none : .enhancement
            } else {
                enhancementService.isEnhancementEnabled = true
            }
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringEnhancement = $0
            syncEnhancementPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .enhancement), arrowEdge: .bottom) {
            EnhancementPromptPopover()
                .environmentObject(enhancementService)
                .onHover {
                    isHoveringEnhancementPopover = $0
                    syncEnhancementPopoverVisibility()
                }
        }
    }

    private func syncEnhancementPopoverVisibility() {
        let shouldShow = isHoveringEnhancement || isHoveringEnhancementPopover
        if shouldShow {
            enhancementDismissWorkItem?.cancel()
            enhancementDismissWorkItem = nil
            activePopover = .enhancement
        } else {
            enhancementDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [activePopoverBinding = $activePopover] in
                if activePopoverBinding.wrappedValue == .enhancement {
                    activePopoverBinding.wrappedValue = .none
                }
            }
            enhancementDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Power Mode Button Component
struct RecorderPowerModeButton: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @Binding var activePopover: ActivePopoverState
    let buttonSize: CGFloat
    let padding: EdgeInsets
    @State private var isHoveringPower: Bool = false
    @State private var isHoveringPowerPopover: Bool = false
    @State private var powerDismissWorkItem: DispatchWorkItem?
    
    init(activePopover: Binding<ActivePopoverState>, buttonSize: CGFloat = 28, padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 7)) {
        self._activePopover = activePopover
        self.buttonSize = buttonSize
        self.padding = padding
    }
    
    var body: some View {
        RecorderToggleButton(
            isEnabled: !powerModeManager.enabledConfigurations.isEmpty,
            icon: powerModeManager.enabledConfigurations.isEmpty ? "✨" : (powerModeManager.currentActiveConfiguration?.emoji ?? "✨"),
            color: .orange,
            disabled: powerModeManager.enabledConfigurations.isEmpty
        ) {
            activePopover = activePopover == .power ? .none : .power
        }
        .frame(width: buttonSize)
        .padding(padding)
        .onHover {
            isHoveringPower = $0
            syncPowerPopoverVisibility()
        }
        .popover(isPresented: .constant(activePopover == .power), arrowEdge: .bottom) {
            PowerModePopover()
                .onHover {
                    isHoveringPowerPopover = $0
                    syncPowerPopoverVisibility()
                }
        }
    }

    private func syncPowerPopoverVisibility() {
        let shouldShow = isHoveringPower || isHoveringPowerPopover
        if shouldShow {
            powerDismissWorkItem?.cancel()
            powerDismissWorkItem = nil
            activePopover = .power
        } else {
            powerDismissWorkItem?.cancel()
            let work = DispatchWorkItem { [activePopoverBinding = $activePopover] in
                if activePopoverBinding.wrappedValue == .power {
                    activePopoverBinding.wrappedValue = .none
                }
            }
            powerDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// MARK: - Settings Info Component
struct RecorderSettingsInfo: View {
    @ObservedObject var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    let isCompact: Bool
    @State private var isExpanded: Bool = false

    init(whisperState: WhisperState, isCompact: Bool = false) {
        self.whisperState = whisperState
        self.isCompact = isCompact
    }

    private var transcriptionModelInfo: (name: String, type: String)? {
        guard let model = whisperState.currentTranscriptionModel else { return nil }
        return (model.displayName, model.provider.rawValue)
    }

    private var activePresetName: String? {
        if let activeConfig = powerModeManager.currentActiveConfiguration {
            return "\(activeConfig.emoji) \(activeConfig.name)"
        }
        return nil
    }

    private var enhancementPromptName: String? {
        guard enhancementService.isEnhancementEnabled,
              let prompt = enhancementService.activePrompt else { return nil }
        return prompt.title
    }

    private var aiProviderName: String? {
        guard enhancementService.isEnhancementEnabled else { return nil }
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedAIProvider") {
            // Map the provider key to display name
            switch savedProvider {
            case "openai": return "OpenAI"
            case "anthropic": return "Anthropic"
            case "gemini": return "Gemini"
            case "groq": return "Groq"
            case "ollama": return "Ollama"
            case "openRouter": return "OpenRouter"
            case "custom": return "Custom"
            default: return savedProvider
            }
        }
        return nil
    }

    var body: some View {
        if isCompact {
            // Compact view for NotchRecorder
            HStack(spacing: 6) {
                if let modelInfo = transcriptionModelInfo {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(modelInfo.name)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                if let presetName = activePresetName {
                    Text(presetName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
            }
        } else {
            // Expandable view for MiniRecorder
            VStack(spacing: 4) {
                // Always visible summary
                HStack(spacing: 8) {
                    if let modelInfo = transcriptionModelInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                            Text(modelInfo.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    if let presetName = activePresetName {
                        Text(presetName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8))
                    }

                    Spacer()

                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

                // Expanded details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        if let modelInfo = transcriptionModelInfo {
                            HStack(spacing: 4) {
                                Text("Model:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("\(modelInfo.name) (\(modelInfo.type))")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }

                        if let promptName = enhancementPromptName {
                            HStack(spacing: 4) {
                                Text("Prompt:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(promptName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.blue.opacity(0.7))
                            }
                        }

                        if let providerName = aiProviderName {
                            HStack(spacing: 4) {
                                Text("AI:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(providerName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.green.opacity(0.7))
                            }
                        }

                        if let langCode = UserDefaults.standard.string(forKey: "SelectedLanguage") {
                            HStack(spacing: 4) {
                                Text("Lang:")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(languageName(for: langCode))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func languageName(for code: String) -> String {
        if code == "en" { return "English" }
        if let model = whisperState.currentTranscriptionModel,
           let langName = model.supportedLanguages[code] {
            return langName
        }
        return code.uppercased()
    }
}

// MARK: - Status Display Component
struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeter: AudioMeter
    let menuBarHeight: CGFloat?

    init(currentState: RecordingState, audioMeter: AudioMeter, menuBarHeight: CGFloat? = nil) {
        self.currentState = currentState
        self.audioMeter = audioMeter
        self.menuBarHeight = menuBarHeight
    }

    var body: some View {
        Group {
            if currentState == .enhancing {
                VStack(spacing: 2) {
                    Text("Enhancing")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    ProgressAnimation(animationSpeed: 0.15)
                }
            } else if currentState == .transcribing {
                VStack(spacing: 2) {
                    Text("Transcribing")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    ProgressAnimation(animationSpeed: 0.12)
                }
            } else if currentState == .recording {
                AudioVisualizer(
                    audioMeter: audioMeter,
                    color: .white,
                    isActive: currentState == .recording
                )
                .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
            } else {
                StaticVisualizer(color: .white)
                    .scaleEffect(y: menuBarHeight != nil ? min(1.0, (menuBarHeight! - 8) / 25) : 1.0, anchor: .center)
            }
        }
    }
}