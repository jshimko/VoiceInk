# VoiceInk Development Guide for AI Agents

## Purpose

VoiceInk is a native macOS voice-to-text application that provides accurate, privacy-focused transcription with AI enhancement capabilities. This is a **configurable fork** with privacy-by-default settings, where all external communication is optional and controlled via configuration. This directory contains the complete Swift/SwiftUI application source code.

## Domain Context

Voice transcription and text processing application for macOS, featuring:

- Real-time voice recording and transcription
- Multiple transcription backends (local Whisper, cloud services, native Apple)
- AI-powered text enhancement and formatting
- Context-aware Power Mode for automatic configuration
- Privacy-first design with 100% offline capability
- **Fully configurable fork architecture** - customize branding, URLs, and features
- **Privacy-by-default** - all external services are opt-in via configuration

## Dependencies

- **Internal**: Core modules are self-contained within VoiceInk/
- **Build Tools**:
  - Taskfile (build automation - `brew install go-task`)
  - Xcode 15+ (Swift compiler and toolchain)
- **External Frameworks**:
  - whisper.xcframework (speech recognition)
  - Sparkle (auto-updates - **optional**, controlled via config)
  - KeyboardShortcuts (global hotkeys)
  - FluidAudio (Parakeet model support)
  - MediaRemoteAdapter (media playback control)
  - LaunchAtLogin (startup management)
  - SelectedTextKit (text selection extraction)

## Dependents

This is the main application - no internal dependents.

---

## ⚠️ CRITICAL CONSTRAINTS

### NEVER Modify Without Coordination:

- **WhisperState.swift**: Central state management - changes affect entire app
- **VoiceInk.swift**: App initialization - incorrect changes break startup
- **Info.plist**: App permissions - wrong values crash the app
- **Model migrations**: SwiftData schema changes require migration code
- **AppConfig.swift**: Central configuration singleton - affects app identity and features
- **Fork.plist**: Fork configuration - controls all feature flags and external URLs
- **Taskfile.yaml**: Build system configuration - affects all build/test/release processes

### ALWAYS Follow These Rules:

- **State Management**: Use @Published properties in ObservableObject classes
- **UI Updates**: All UI changes must be on @MainActor
- **Audio Handling**: Check microphone permissions before recording
- **File Operations**: Use Application Support directory for user data
- **Error Handling**: Use Logger for debugging, show user-friendly messages
- **Memory Management**: Clean up audio files and transcriptions per user settings

### Performance Requirements:

- Transcription must start within 100ms of recording stop
- UI must remain responsive during transcription
- Memory usage should not exceed 500MB during normal operation

### Security Requirements:

- NEVER send audio data to cloud without explicit user consent
- API keys must be stored in Keychain, not UserDefaults
- Obfuscate sensitive data in logs
- Validate all user input before processing

---

## Architecture Overview

### High-Level Design Pattern

**MVVM + Service Layer Architecture**

```
Views (SwiftUI) → ViewModels (@StateObject) → Services → External APIs/Frameworks
                                ↓
                        Models (SwiftData)
```

### Key Design Decisions

1. **Why SwiftUI over AppKit**: Modern declarative UI, better state management
2. **Why SwiftData over Core Data**: Simpler API, Swift-native, type-safe
3. **Why Service Layer**: Separation of concerns, testability, multiple backend support
4. **Why ObservableObject pattern**: SwiftUI integration, reactive updates
5. **Why Fork Configuration System**: Enable customization without code changes, privacy-by-default
6. **Why Conditional Compilation**: Optional features (Sparkle) without forcing dependencies

---

## Fork Configuration System

### Configuration Architecture

```
Fork.plist → AppConfig.swift (Singleton) → UI Components & Services
                    ↓
            Feature Flags & URLs
```

### How It Works

1. **Fork.plist**: Your organization's configuration (gitignored)
2. **Fork.plist.template**: Template for configuration (tracked in git)
3. **AppConfig.swift**: Singleton that reads and provides configuration
4. **UI Components**: Conditionally render based on configuration flags

### Key Configuration Options

| Configuration             | Purpose                                       | Default                |
| ------------------------- | --------------------------------------------- | ---------------------- |
| `BundleIdentifierPrefix`  | Your org's bundle ID (e.g., `com.yourdomain`) | `com.voiceink`         |
| `SupportEmail`            | User support email                            | `support@voiceink.app` |
| `EnableAutoUpdates`       | Enable Sparkle auto-updates                   | `false`                |
| `EnableLicenseValidation` | Enable license checking                       | `false`                |
| `EnableAnnouncements`     | Enable announcement service                   | `false`                |
| `EnableAnalytics`         | Enable usage analytics                        | `false`                |
| `ShowPurchaseOptions`     | Show purchase UI                              | `false`                |
| `ShowCommunityLinks`      | Show community links                          | `false`                |

---

## Build System

### Taskfile Integration

The project uses **Taskfile** for unified build automation:

```bash
# One-time setup
brew install go-task

# Common tasks
task --list           # Show all available tasks
task setup           # Complete project setup
task build           # Build debug version
task build:open      # Build and launch app
task test            # Run all tests
task release         # Create release build
task install         # Install locally built app
task clean           # Clean build artifacts
```

### Build Configurations

- **Debug**: Development build with debug symbols
- **Release**: Optimized production build
- **Fork**: Custom build with your Fork.plist configuration

---

## Established Patterns

### Pattern: Service Initialization

- **When to use**: Creating any new service class
- **Implementation**: Initialize in VoiceInkApp.swift, pass via dependency injection
- **Example**:

```swift
let aiService = AIService()
_aiService = StateObject(wrappedValue: aiService)
```

- **File**: VoiceInk/VoiceInk.swift:62-63

### Pattern: View State Management

- **When to use**: Managing view-specific state
- **Implementation**: Use @StateObject for owned objects, @ObservedObject for injected
- **Example**:

```swift
@StateObject private var whisperState: WhisperState
@ObservedObject var enhancementService: AIEnhancementService
```

- **File**: VoiceInk/Views/ContentView.swift

### Pattern: Async Operations

- **When to use**: Network calls, file I/O, transcription
- **Implementation**: Use Swift async/await with Task
- **Example**:

```swift
Task {
   await whisperState.transcribeAudio(fileURL: url)
}
```

- **File**: VoiceInk/Whisper/WhisperState.swift

### Pattern: Fork Configuration

- **When to use**: Customizing app for different organizations or deployments
- **Implementation**: Edit Fork.plist, AppConfig reads and provides values
- **Example**:

```swift
// In AppConfig.swift
let config = AppConfig.shared
if config.enableAutoUpdates {
    // Initialize Sparkle
}

// In UI components
if AppConfig.shared.showPurchaseOptions {
    PurchaseView()
}
```

- **Files**: Fork.plist, VoiceInk/AppConfig.swift

### Pattern: Feature Flags

- **When to use**: Conditionally enabling/disabling features
- **Implementation**: Define in Fork.plist, check via AppConfig
- **Example**:

```swift
if AppConfig.shared.enableLicenseValidation {
    // Original license logic
} else {
    // Operate as fully licensed
    licenseState = .licensed
}
```

- **File**: VoiceInk/Models/LicenseViewModel.swift:37-77

### Pattern: Power Mode UI Flag Initialization

- **When to use**: App initialization for feature flags that depend on user data
- **Implementation**: Check UserDefaults, set default based on existing configuration
- **Example**:

```swift
// In VoiceInkApp.init()
if UserDefaults.standard.object(forKey: "powerModeUIFlag") == nil {
    let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
    UserDefaults.standard.set(hasEnabledPowerModes, forKey: "powerModeUIFlag")
}
```

- **File**: VoiceInk/VoiceInk.swift:36-40

---

## Making Changes

### Before Starting

1. Check current git status: `git status`
2. Verify Xcode project builds: `Cmd+B`
3. Run existing tests: `Cmd+U`
4. Related files that often change together:
   - WhisperState.swift + Recorder.swift (recording changes)
   - AIService.swift + AIEnhancementService.swift (AI features)
   - Views/ + Models/ (UI changes)
   - ParakeetTranscriptionService.swift + WhisperState+Parakeet.swift (Parakeet model changes)
   - SelectedTextService.swift + SelectedTextKit (text selection changes)

### During Development

- Use existing patterns from: VoiceInk/Services/ for new services
- Follow conventions in: VoiceInk/Views/ for UI components
- Performance considerations: Profile with Instruments for memory/CPU
- Security checklist:
  ✓ API keys in Keychain
  ✓ Permissions checked
  ✓ User data encrypted
  ✓ No sensitive data in logs

### Testing Requirements

- Unit tests required for: All Service classes, Model logic
- UI tests required for: Main user flows, settings changes
- Test file naming: \*Tests.swift in VoiceInkTests/
- Coverage requirement: 70% for new code
- Run tests: `Cmd+U` in Xcode

---

## Directory Structure

```
VoiceInk/
├── Fork.plist                  # Fork configuration (gitignored)
├── Fork.plist.template         # Configuration template
├── Taskfile.yaml               # Build automation configuration
├── VoiceInk/                   # Main application source
│   ├── AppDelegate.swift      # macOS app lifecycle
│   ├── VoiceInk.swift         # Main app entry point
│   ├── AppConfig.swift        # Configuration singleton
│   ├── AppIntents/            # Shortcuts app integration
│   ├── Models/                # Data models and ViewModels
│   │   ├── Transcription.swift    # Core data model
│   │   ├── AIPrompts.swift        # AI prompt templates
│   │   └── LicenseViewModel.swift # License management
│   ├── Views/                 # SwiftUI views
│   │   ├── ContentView.swift     # Main window
│   │   ├── AI Models/            # Model management UI
│   │   └── Common/               # Reusable components
│   ├── Services/              # Business logic layer
│   │   ├── AIService.swift                    # AI provider management
│   │   ├── TranscriptionService.swift         # Transcription interface
│   │   ├── ParakeetTranscriptionService.swift # Parakeet local transcription
│   │   ├── SelectedTextService.swift          # Text selection extraction
│   │   ├── PolarService.swift                 # Analytics (optional)
│   │   └── CloudTranscription/                # Cloud provider implementations
│   ├── PowerMode/             # Context-aware features
│   │   ├── PowerModeView.swift   # Configuration UI
│   │   └── ActiveWindowService.swift # App detection
│   ├── Whisper/               # Local transcription
│   │   ├── WhisperState.swift    # Central state management
│   │   └── WhisperContext.swift  # Whisper.cpp wrapper
│   ├── Resources/             # Assets and resources
│   └── Notifications/         # In-app notifications
├── VoiceInkTests/             # Unit tests
│   ├── ConfigurationTests.swift  # Fork configuration tests
│   ├── FeatureFlagTests.swift    # Feature flag tests
│   ├── IntegrationTests.swift    # Integration tests
│   └── MigrationTests.swift      # Migration tests
├── scripts/                   # Build and automation scripts
│   ├── setup-fork.sh          # Interactive fork setup
│   ├── setup-project.sh       # Project setup
│   ├── build-app.sh           # App building
│   ├── build-whisper.sh       # Whisper framework build
│   ├── run-tests.sh           # Test runner
│   ├── create-release.sh      # Release creation
│   └── install.sh             # Local installation
├── docs/                      # Documentation
│   ├── FORK_GUIDE.md          # Fork configuration guide
│   ├── build.md               # Build instructions
│   ├── API_REFERENCE.md       # API documentation
│   ├── ARCHITECTURE.md        # Architecture overview
│   ├── MIGRATION.md           # Migration guides
│   └── PRIVACY_AUDIT.md       # Privacy analysis
└── .gitignore                 # Includes Fork.plist
```

## File Naming Conventions

- Views: \*View.swift (e.g., SettingsView.swift)
- Services: *Service.swift or *Manager.swift
- Models: Singular nouns (e.g., Transcription.swift)
- ViewModels: \*ViewModel.swift
- Tests: \*Tests.swift

---

## Core APIs & Interfaces

### API: WhisperState.toggleRecord()

- **Purpose**: Start/stop audio recording
- **Parameters**: None (async)
- **Returns**: Nothing
- **Throws**: Recording errors propagated
- **Usage Pattern**:

```swift
Task { await whisperState.toggleRecord() }
```

- **Don't**: Call without checking permissions first

### API: AIService.enhanceText()

- **Purpose**: Enhance transcribed text with AI
- **Parameters**: text: String, prompt: String
- **Returns**: Enhanced text String
- **Throws**: Network/API errors
- **Usage Pattern**: Use with selected AI provider
- **Don't**: Call without API key configured

### API: TranscriptionService.transcribe()

- **Purpose**: Convert audio to text
- **Parameters**: audioURL: URL
- **Returns**: Transcribed text
- **Throws**: Transcription errors
- **Usage Pattern**: Implement protocol for new providers
- **Don't**: Process files > 25MB without chunking

### API: ParakeetTranscriptionService.loadModel()

- **Purpose**: Load a specific Parakeet model version (v2 or v3)
- **Parameters**: model: ParakeetModel
- **Returns**: Nothing (async)
- **Throws**: ASR initialization errors
- **Usage Pattern**:

```swift
let service = ParakeetTranscriptionService()
try await service.loadModel(for: parakeetModel)
```

- **Don't**: Call transcribe() without loading model first
- **Breaking Change**: Now requires ParakeetModel parameter (previously took no parameters)

### API: SelectedTextService.fetchSelectedText()

- **Purpose**: Fetch currently selected text from active application
- **Parameters**: None
- **Returns**: Optional String with selected text (async)
- **Throws**: No throws, returns nil on failure
- **Usage Pattern**:

```swift
if let text = await SelectedTextService.fetchSelectedText() {
    // Process selected text
}
```

- **Don't**: Use clipboard manipulation directly
- **Breaking Change**: Changed from synchronous clipboard access to async SelectedTextKit integration

### API: WhisperState.showParakeetModelInFinder()

- **Purpose**: Open Finder to show cached Parakeet model location
- **Parameters**: model: ParakeetModel
- **Returns**: Nothing
- **Throws**: Nothing
- **Usage Pattern**:

```swift
whisperState.showParakeetModelInFinder(parakeetModel)
```

- **Breaking Change**: Now requires ParakeetModel parameter (previously took no parameters)

---

## State Management

### State Patterns

- **State container**: SwiftUI @StateObject + ObservableObject
- **State structure**:
  - App-wide: WhisperState, AIService
  - View-specific: Local @State
  - Persistent: @AppStorage, SwiftData
- **Update patterns**: @Published properties trigger UI updates
- **Side effects**: Task { } for async operations
- **Example**:

```swift
@Published var isRecording = false {
    didSet {
        Task { await updateUI() }
    }
}
```

---

## Error Handling

### Error Patterns

- **Error types**: Custom enums conforming to Error
- **Handling strategy**: do-try-catch with specific error handling
- **Logging**: Logger(subsystem: "\(AppConfig.shared.loggerSubsystem)", category: "Feature")
- **User feedback**: Show alerts for user errors, log system errors
- **Recovery**: Retry with exponential backoff for network errors

Example:

```swift
do {
    try await performOperation()
} catch NetworkError.timeout {
    // Retry logic
} catch {
    logger.error("Operation failed: \(error)")
}
```

---

## Testing Patterns

### Test Structure

- **Setup pattern**: XCTestCase with setUp()/tearDown()
- **Mocking approach**: Protocol-based dependency injection
- **Assertion patterns**: XCTAssert\*, XCTExpectation for async
- **Test data**: Fixtures in VoiceInkTests/Fixtures/
- **Example test**: VoiceInkTests/WhisperStateTests.swift

### Test Categories

1. **Configuration Tests** (`ConfigurationTests.swift`)

   - Fork.plist loading
   - Default values
   - Feature flag behavior

2. **Feature Flag Tests** (`FeatureFlagTests.swift`)

   - Conditional feature enabling
   - UI element visibility
   - Service initialization

3. **Integration Tests** (`IntegrationTests.swift`)

   - End-to-end workflows
   - Service interactions
   - Data persistence

4. **Migration Tests** (`MigrationTests.swift`)
   - Schema migrations
   - Data upgrades
   - Backward compatibility

### Running Tests

```bash
# All tests
task test

# Specific test categories
task test:unit
task test:ui
task test:fork

# With coverage
task test:coverage
```

---

## HOW TO: Add a New Transcription Provider

1. Create protocol implementation:

   - Add to Services/CloudTranscription/
   - Implement TranscriptionService protocol
   - Follow pattern in OpenAICompatibleTranscriptionService.swift

2. Register in PredefinedModels:

   - Add to Models/PredefinedModels.swift
   - Include model metadata

3. Update UI:

   - Add configuration in Views/AI Models/
   - Follow ModelCardRowView pattern

4. Test:

   - Unit test the service
   - UI test the configuration flow

5. Document:
   - Add to README if significant

---

## HOW TO: Create Your Own Fork

1. Setup your fork:

   ```bash
   # Run interactive setup
   ./scripts/setup-fork.sh

   # Or manually:
   cp Fork.plist.template Fork.plist
   # Edit Fork.plist with your configuration
   ```

2. Add Fork.plist to Xcode:

   - Open VoiceInk.xcodeproj
   - Drag Fork.plist into project navigator
   - Ensure it's added to VoiceInk target

3. Configure your features:

   - Set feature flags in Fork.plist
   - Configure URLs for external services
   - Set bundle identifier and support email

4. Build your fork:

   ```bash
   task build
   # Or for release:
   task release
   ```

5. Test fork-specific features:

   ```bash
   task test:fork
   ```

---

## HOW TO: Configure Feature Flags

1. Edit Fork.plist:

   ```xml
   <key>EnableAutoUpdates</key>
   <true/>  <!-- Enable Sparkle updates -->

   <key>ShowPurchaseOptions</key>
   <false/> <!-- Disable purchase UI -->
   ```

2. Feature flag usage in code:

   ```swift
   if AppConfig.shared.enableLicenseValidation {
       // License logic
   }
   ```

3. Available flags:

   - `EnableAutoUpdates`: Sparkle auto-updates
   - `EnableLicenseValidation`: License checking
   - `EnableAnnouncements`: Announcement service
   - `EnableAnalytics`: Usage analytics
   - `ShowPurchaseOptions`: Purchase UI
   - `ShowCommunityLinks`: Community links
   - `ShowDonationLink`: Donation/tip jar

---

## HOW TO: Build and Install Locally

1. Complete setup:

   ```bash
   task setup
   ```

2. Build debug version:

   ```bash
   task build
   ```

3. Build release version:

   ```bash
   task release
   ```

4. Install locally:

   ```bash
   task install
   ```

5. Clean and rebuild:

   ```bash
   task clean
   task build
   ```

---

## HOW TO: Fix a Bug

1. Reproduce:

   - Run app from Xcode
   - Enable verbose logging: logger.debug()

2. Debug:

   - Use Xcode breakpoints
   - Check Console.app for system logs
   - Profile with Instruments if performance

3. Fix pattern:

   - Minimal change to fix issue
   - Add regression test
   - Update affected documentation

4. Test:

   - Run full test suite
   - Manual testing of affected flows

5. Verify:
   - Check no new warnings
   - Ensure performance unchanged

---

## Performance & Optimization

### Performance Requirements

- **Response time**: < 100ms for UI interactions
- **Memory limits**: < 500MB typical, < 1GB peak
- **Optimization patterns**:
  - Lazy loading for models
  - Background queues for heavy work
  - Caching transcription results
- **Profiling**: Use Instruments (Time Profiler, Allocations)
- **Bottlenecks**:
  - Model loading (cache in memory)
  - Large audio files (stream processing)

---

## Integration Points

### External Integrations

- **Whisper.cpp**: Local transcription via C++ framework
- **Cloud APIs**: OpenAI, Anthropic, Groq via REST
- **macOS APIs**:
  - AVFoundation for audio
  - ScreenCaptureKit for context
  - Accessibility for window detection
- **SelectedTextKit**: Text selection extraction from active applications
- **Sparkle**: Auto-update framework (**optional**, controlled by `EnableAutoUpdates`)
- **Keychain**: Secure credential storage

### Optional Services (Controlled by Configuration)

- **License Validation**: Disabled by default (`EnableLicenseValidation`)
- **Analytics/Telemetry**: Disabled by default (`EnableAnalytics`)
- **Announcements Service**: Disabled by default (`EnableAnnouncements`)
- **Auto-Updates**: Disabled by default (`EnableAutoUpdates`)

All external services are **opt-in** and controlled via Fork.plist configuration.

---

## Known Issues & Gotchas

### Issue: Microphone permission denied silently

**Workaround**: Check AVCaptureDevice.authorizationStatus before recording

### Issue: SwiftData migration fails on schema change

**Workaround**: Implement proper VersionedSchema migrations

### Issue: Memory spike during long recordings

**Workaround**: Stream audio to disk, process in chunks

### Non-Obvious Requirements:

- App must work completely offline (local models)
- Must respect system audio routing changes
- Power Mode requires Accessibility permissions
- Screen capture for context requires permission
- **Fork.plist must be added to Xcode project after creation**
- **Bundle identifier changes require clean build**
- **VoiceInk.entitlements uses dynamic bundle identifier via $(PRODUCT_BUNDLE_IDENTIFIER)**
- **Whisper.cpp framework must be located at ../whisper.cpp relative to project root**

### Historical Context:

- Originally used Core ML, switched to Whisper for accuracy
- Power Mode added due to user requests for automation
- Multiple transcription backends for flexibility/reliability
- **Forked to enable privacy-focused customization (2025)**
- **All external communication made optional via configuration**

### Fork-Specific Gotchas:

**Issue: Fork.plist not found at runtime**

**Solution**: Must add Fork.plist to Xcode project and ensure it's in app bundle

**Issue: Sparkle framework not found**

**Solution**: Conditional compilation with `#if canImport(Sparkle)`

**Issue: Feature flags not taking effect**

**Solution**: Clean build after Fork.plist changes (`task clean && task build`)

**Issue: ParakeetTranscriptionService model version switching**

**Explanation**: Service maintains activeVersion state and automatically switches between v2/v3 models, cleaning up the previous model when switching.

**Solution**: Always call loadModel() before transcribe() to ensure correct version is loaded. Don't assume models persist across calls.

---

## Privacy & Security Enhancements

### Privacy-by-Default Configuration

All external communication is **disabled by default** and must be explicitly enabled:

| Feature            | Default     | Privacy Impact                 |
| ------------------ | ----------- | ------------------------------ |
| Auto-updates       | ❌ Disabled | No update server communication |
| License validation | ❌ Disabled | No license server checks       |
| Analytics          | ❌ Disabled | No usage data collection       |
| Announcements      | ❌ Disabled | No announcement fetching       |
| Crash reporting    | ❌ Disabled | No crash data sent             |

### Enabling External Services

To enable any external service, explicitly configure in Fork.plist:

```xml
<!-- Only enable what you need -->
<key>EnableAutoUpdates</key>
<true/>

<key>SparkleUpdateURL</key>
<string>https://your-server.com/appcast.xml</string>
```

### Data Privacy Guarantees

1. **No hardcoded external URLs** - All URLs are configurable
2. **No telemetry by default** - Must explicitly enable
3. **Local-first operation** - Works fully offline
4. **Transparent networking** - All network calls are user-initiated or explicitly configured
5. **API keys in Keychain** - Never stored in UserDefaults or code

---

## Development Tips

### Swift/SwiftUI Best Practices:

- Prefer `if let` over force unwrapping
- Use `@MainActor` for UI updates
- Leverage property wrappers effectively
- Keep views small and composable

### Common Pitfalls to Avoid:

- Don't block main thread with transcription
- Don't store sensitive data in UserDefaults
- Don't assume permissions are granted
- Don't ignore memory warnings

### Debugging Helpers:

- Enable "Debug > Debug Workflow > View Debugging"
- Use Console.app for system-level logs
- Add `.border(Color.red)` to debug view layouts
- Use `po` in LLDB for object inspection

---

## Quick Reference

### Key Files:

- Main app: `VoiceInk/VoiceInk.swift`
- Recording: `VoiceInk/Whisper/WhisperState.swift`
- UI entry: `VoiceInk/Views/ContentView.swift`
- AI logic: `VoiceInk/Services/AIService.swift`

### Important UserDefaults Keys:

- "selectedTranscriptionModel"
- "enableAIEnhancement"
- "RecorderType" (mini/standard)
- "powerModeConfigs"

### Notification Names:

- `.transcriptionCreated`
- `.modelDownloadProgress`
- `.recordingStateChanged`

### Build Commands:

**Using Taskfile (Recommended):**

```bash
# Setup (one-time)
task setup

# Build operations
task build           # Debug build
task build:open      # Build and launch app
task release        # Release build
task install        # Install locally
task clean          # Clean artifacts

# Testing
task test           # Run all tests
task test:unit      # Unit tests only
task test:ui        # UI tests only
task test:fork      # Fork configuration tests

# Development
task dev            # Build and watch for changes
task format         # Format Swift code
```

**Direct Xcode commands (alternative):**

```bash
# Build
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk build

# Test
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk

# Clean
xcodebuild clean -project VoiceInk.xcodeproj -scheme VoiceInk
```

---

## Fork Maintenance

### Updating from Upstream

1. Add upstream remote (one-time):

   ```bash
   git remote add upstream https://github.com/Beingpax/VoiceInk.git
   ```

2. Fetch and merge updates:

   ```bash
   git fetch upstream
   git merge upstream/main
   ```

3. Resolve conflicts in Fork.plist and AppConfig.swift carefully

### Managing Configuration Changes

- **Fork.plist changes**: Always test feature flags after changes
- **AppConfig.swift changes**: Ensure backward compatibility
- **Bundle ID changes**: Requires clean build and may affect user data

### Testing Fork-Specific Features

```bash
# Test configuration loading
task test:fork

# Verify feature flags
task test:features

# Integration tests
task test:integration
```

---

## Remember

This codebase prioritizes:

1. **Privacy**: Local-first, optional cloud, privacy-by-default configuration
2. **Performance**: Responsive UI, fast transcription
3. **Reliability**: Multiple fallback options
4. **User Experience**: Simple, intuitive interface
5. **Customizability**: Fork-friendly architecture with configuration system

When developing, always consider:

- Will this work offline?
- Is the user's data secure?
- Does this maintain backward compatibility?
- Is the performance impact acceptable?
- Are external services properly gated by configuration?
- Will this work for all fork configurations?

Focus on maintaining the existing patterns and architecture. The codebase is well-structured - follow the established conventions for consistency. The fork configuration system enables customization without code changes.
