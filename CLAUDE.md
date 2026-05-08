# VoiceInk Development Guide for AI Agents

> **Last verified**: 2026-04-26 against commit `02d063c`

## Purpose

VoiceInk is a native macOS voice-to-text application that provides accurate, privacy-focused transcription with AI enhancement capabilities. This is a **configurable fork** with privacy-by-default settings, where all external communication is optional and controlled via configuration. This directory contains the complete Swift/SwiftUI application source code.

## Domain Context

Voice transcription and text processing application for macOS, featuring:

- Real-time voice recording and transcription
- Multiple transcription backends (local Whisper, FluidAudio/Parakeet, native Apple Speech, plus 8+ cloud providers)
- AI-powered text enhancement and formatting (cloud LLMs + local Ollama)
- Context-aware Power Mode for automatic per-app configuration
- Privacy-first design with 100% offline capability
- Custom vocabulary and word replacement post-processing
- **Fully configurable fork architecture** — customize branding, URLs, and features
- **Privacy-by-default** — all external services are opt-in via configuration

## Dependencies

- **Internal**: Core modules are self-contained within `VoiceInk/`.
- **Build Tools**:
  - Taskfile (build automation — `brew install go-task`) — recommended
  - Make (alternative, simpler — no extra install)
  - Xcode 15+ (Swift compiler and toolchain)
- **Swift Package dependencies** (resolved by Xcode/SPM):
  - whisper.xcframework (local Whisper transcription, built from `whisper.cpp`)
  - FluidAudio (Parakeet model support — formerly bundled as a separate service)
  - Sparkle (auto-updates — **optional**, gated by `EnableAutoUpdates`)
  - KeyboardShortcuts (global hotkeys)
  - MediaRemoteAdapter (media playback control)
  - LaunchAtLogin (startup management)
  - SelectedTextKit (text selection extraction from active apps)

## Dependents

This is the main application — no internal dependents.

---

## ⚠️ CRITICAL CONSTRAINTS

### NEVER Modify Without Coordination:

- **`VoiceInk/Transcription/Engine/VoiceInkEngine.swift`**: Central recording/transcription engine — changes affect the entire recording pipeline
- **`VoiceInk/VoiceInk.swift`**: App initialization and dependency-injection chain — incorrect changes break startup
- **`VoiceInk/Info.plist`**: App permissions — wrong values crash the app
- **SwiftData schema** (`Transcription`, `VocabularyWord`, `WordReplacement` models): schema changes require migration code; the dictionary store also has CloudKit configuration (see `VoiceInk.swift:191-219`)
- **`VoiceInk/AppConfig.swift`**: Central configuration singleton — affects app identity and feature gating
- **`Fork.plist`**: Fork configuration — controls all feature flags and external URLs (gitignored)
- **`Taskfile.yaml`** and **`Makefile`**: Build system configuration — affects all build/test/release flows
- **`VoiceInk.entitlements` / `VoiceInk.local.entitlements`**: Capabilities — wrong values break sandboxing or signing

### ALWAYS Follow These Rules:

- **State Management**: Use `@Published` properties on `ObservableObject` classes; expose via `@EnvironmentObject` from `VoiceInkApp`.
- **UI Updates**: All UI mutations must be on `@MainActor`.
- **Audio Handling**: Check microphone permissions before recording (`AVCaptureDevice.authorizationStatus(for: .audio)`).
- **File Operations**: Use the per-fork Application Support directory (`AppConfig.shared.applicationSupportPath`) for user data — never the shared default.
- **Error Handling**: Use `Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "Feature")`; show user-friendly alerts for user-facing failures.
- **Memory Management**: Clean up audio files and transcriptions per user settings (`IsAudioCleanupEnabled`, `IsTranscriptionCleanupEnabled`).
- **Bundle identifiers**: Always derive from `AppConfig.shared.mainBundleIdentifier` rather than hardcoding `com.voiceink.VoiceInk` — fork bundle IDs vary.

### Performance Requirements:

- Transcription must start within 100ms of recording stop.
- UI must remain responsive during transcription.
- Memory usage should not exceed ~500MB during normal operation.

### Security Requirements:

- NEVER send audio data to cloud without explicit user consent.
- API keys must be stored in Keychain (`KeychainService.swift`), not UserDefaults.
- Obfuscate sensitive data in logs (`Obfuscator.swift`).
- Validate all user input before processing.

---

## Architecture Overview

### High-Level Design Pattern

**MVVM + Service Layer + Engine Pipeline**

```
Views (SwiftUI) ─► EnvironmentObjects (VoiceInkEngine, *ModelManager, AIEnhancementService)
                       │
                       ▼
         VoiceInkEngine ─► Recorder → TranscriptionService (registry) ─► Pipeline (post-processing)
                       │                       │                                   │
                       ▼                       ▼                                   ▼
                  RecorderUIManager     Whisper / FluidAudio /         WordReplacement / Vocabulary /
                                        Cloud / Native providers       Filler-word filtering / Enhancement
                       │
                       ▼
                  Models (SwiftData: Transcription, VocabularyWord, WordReplacement)
```

`VoiceInkEngine` owns the recording lifecycle and orchestrates the transcription pipeline. The provider implementation is pluggable through `TranscriptionService` (protocol) and selected via `TranscriptionModelManager` based on the user's choice in settings.

### Key Design Decisions

1. **SwiftUI over AppKit**: declarative UI, better state management.
2. **SwiftData over Core Data**: simpler API, Swift-native, type-safe; uses two stores (`default.store` for transcriptions, `dictionary.store` for vocabulary/replacements).
3. **Service + Engine layering**: `VoiceInkEngine` is the central orchestrator; individual `*Service` and `*Manager` classes are narrow and DI-injected.
4. **Pluggable transcription providers**: each provider conforms to `TranscriptionService` and is dispatched via `TranscriptionServiceRegistry`.
5. **Fork Configuration System**: enables customization without code changes, privacy-by-default.
6. **Conditional compilation**: optional features (Sparkle, CloudKit-syncing dictionary) without forcing dependencies; `LOCAL_BUILD` flag disables CloudKit for ad-hoc-signed builds.

---

## Fork Configuration System

### Configuration Architecture

```
Fork.plist ─► AppConfig.swift (Singleton) ─► UI Components & Services
                       │
                       └─► Feature Flags & URLs
```

### How It Works

1. **`Fork.plist`** — your organization's configuration (gitignored).
2. **`Fork.plist.template`** — template for configuration (tracked in git).
3. **`AppConfig.swift`** — singleton that reads the plist on launch and exposes typed properties.
4. **UI Components & Services** — conditionally render or initialize based on configuration flags.

### Key Configuration Options

| Configuration             | Purpose                                              | Default                |
| ------------------------- | ---------------------------------------------------- | ---------------------- |
| `BundleIdentifierPrefix`  | Your org's bundle ID prefix (e.g. `com.yourdomain`)  | `com.voiceink`         |
| `AppName`                 | User-facing app name                                 | `VoiceInk`             |
| `SupportEmail`            | User support email                                   | `support@voiceink.app` |
| `LoggerSubsystem`         | OSLog subsystem prefix for app logs                  | `<prefix>.voiceink`    |
| `EnableAutoUpdates`       | Initialize Sparkle + check for updates               | `false`                |
| `EnableLicenseValidation` | Run license-check logic (otherwise: always licensed) | `false`                |
| `EnableAnnouncements`     | Fetch in-app announcements                           | `false`                |
| `EnableAnalytics`         | Send Polar analytics events                          | `false`                |
| `ShowPurchaseOptions`     | Show purchase UI                                     | `false`                |
| `ShowCommunityLinks`      | Show community/Discord links                         | `false`                |
| `ShowDonationLink`        | Show donation/tip-jar link                           | `false`                |
| `WebsiteURL` / `DocsURL` / `DiscordURL` / `PurchaseURL` / `DonationURL` / `ChangelogURL` / `LicensePortalURL` | Optional public URLs | `nil` |
| `SparkleUpdateURL` / `LicenseValidationURL` / `AnnouncementsURL` | Service endpoints (only used if matching flag is true) | `nil` |
| `AnalyticsAPIToken` / `AnalyticsOrganizationID` | Polar analytics credentials | `nil` |

`AppConfig` also exposes computed helpers: `mainBundleIdentifier`, `testsBundleIdentifier`, `uiTestsBundleIdentifier`, `applicationSupportPath`, `modelsDirectory`, `hasAnyCommunityLinks`, `shouldShowLicensingUI`.

---

## Build System

Two parallel build interfaces are supported. Pick one:

### 1. Taskfile (recommended for active development)

```bash
# One-time install
brew install go-task

# Most-used tasks
task --list           # full list (47 tasks)
task setup            # full project setup (env check + whisper + project)
task build            # debug build
task build:open       # debug build + launch app
task build:local      # ad-hoc-signed build (no Apple Developer cert required)
task test             # run all tests
task release          # release build
task install          # build + install to /Applications
task clean            # clean build artifacts
task dev              # build and watch for changes
task dev:xcode        # open project in Xcode
task doctor           # diagnose common issues
```

Task groups also exist for `setup:*`, `build:*`, `test:*` (`unit`, `ui`, `coverage`, `filter`, `watch`, `fork`, `features`, `integration`), `clean:*` (`deep`, `full`, `whisper`), `release:*` (`dmg`, `notarize`, `version`), `reset:*` (`all`, `data`, `transcriptions`, `models`, `preferences`), and CI helpers (`ci`, `ci:quick`).

The Taskfile expects `whisper.cpp` cloned as a sibling at `../whisper.cpp` (built into `whisper.xcframework`).

### 2. Makefile (alternative, simpler — no extra dependencies)

```bash
make           # all (= setup + build)
make whisper   # clone/build whisper.xcframework
make build     # debug build
make local     # ad-hoc-signed build to ~/Downloads/VoiceInk.app (no cert)
make run       # launch built app
make dev       # build + run
make clean     # remove build artifacts and dependencies
make help      # list targets
```

The Makefile manages dependencies in `~/VoiceInk-Dependencies/whisper.cpp/` (different from the Taskfile's `../whisper.cpp` — the two systems are independent).

### 3. Local (unsigned) builds

`LocalBuild.xcconfig` + `VoiceInk/VoiceInk.local.entitlements` provide an ad-hoc-signed configuration that skips iCloud/CloudKit entitlements and APS push, so contributors without an Apple Developer account can build and run the app. Triggered via `task build:local` or `make local`. The build sets the `LOCAL_BUILD` Swift compilation flag, which (e.g.) disables CloudKit syncing on the dictionary store in `VoiceInk.swift`.

### 4. Canonical reference

See `BUILDING.md` (project root) for the authoritative end-to-end build guide; `docs/build.md` may exist as a long-form reference.

### Build Configurations

- **Debug**: development build with debug symbols.
- **Release**: optimized production build.
- **Local**: ad-hoc-signed; no CloudKit, no Sparkle pull (depends on Fork.plist), uses `VoiceInk.local.entitlements`.
- **Fork-customized**: any of the above with a custom `Fork.plist`.

---

## Established Patterns

### Pattern: Service Initialization & DI

- **When to use**: creating any new service that should be available across the app.
- **Implementation**: instantiate in `VoiceInkApp.init()`, wrap in `StateObject`, expose to views via `.environmentObject(...)`.
- **Example** (real fragment from `VoiceInk/VoiceInk.swift:96-104`):

```swift
let aiService = AIService()
_aiService = StateObject(wrappedValue: aiService)

let updaterViewModel = UpdaterViewModel()
_updaterViewModel = StateObject(wrappedValue: updaterViewModel)

let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
_enhancementService = StateObject(wrappedValue: enhancementService)
```

The full DI chain in `VoiceInk.swift:96-177` builds (in order): `AIService` → `AIEnhancementService` → model managers (`WhisperModelManager`, `FluidAudioModelManager`, `TranscriptionModelManager`) → `RecorderUIManager` → `VoiceInkEngine` → `HotkeyManager` / `MenuBarManager` / `ActiveWindowService` / `ModelPrewarmService`. Circular references between `VoiceInkEngine` and `RecorderUIManager` are wired up explicitly after construction.

### Pattern: View State Management

- **When to use**: managing view-specific state.
- **Implementation**: `@StateObject` for owned objects, `@EnvironmentObject` for app-wide services injected from `VoiceInkApp`.
- **Example**:

```swift
@EnvironmentObject var engine: VoiceInkEngine
@EnvironmentObject var enhancementService: AIEnhancementService
@StateObject private var localViewModel = SomeFeatureViewModel()
```

### Pattern: Async Operations

- **When to use**: network calls, file I/O, transcription, model loading.
- **Implementation**: Swift `async`/`await` with `Task { ... }` for fire-and-forget from synchronous contexts.
- **Example**:

```swift
Task {
    await engine.toggleRecord(powerModeId: detectedPowerModeId)
}
```

### Pattern: Fork Configuration Lookup

- **When to use**: gating any feature, URL, or service tied to fork identity.
- **Implementation**: read `AppConfig.shared` rather than hardcoding identifiers or URLs.
- **Example**:

```swift
let config = AppConfig.shared
if config.enableAutoUpdates {
    // Initialize Sparkle
}
if config.showPurchaseOptions {
    PurchaseView()
}
```

### Pattern: Feature Flag Early Return

- **When to use**: disabling external-service code paths cleanly.
- **Implementation**: short-circuit at the top of the function so disabled state is the simplest path.
- **Example** (`VoiceInk/Models/LicenseViewModel.swift:44-53`):

```swift
private func loadLicenseState() {
    guard config.enableLicenseValidation else {
        // License validation disabled — operate as fully licensed.
        licenseState = .licensed
        if let storedLicenseKey = licenseManager.licenseKey {
            self.licenseKey = storedLicenseKey
        }
        return
    }
    // …real validation logic…
}
```

### Pattern: Power Mode UI Flag Initialization

- **When to use**: bootstrapping a UI feature flag whose default depends on existing user data.
- **Implementation**: check whether the key is unset, then derive a default from user state.
- **Example** (`VoiceInk/VoiceInk.swift:49-52`):

```swift
if UserDefaults.standard.object(forKey: "powerModeUIFlag") == nil {
    let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
    UserDefaults.standard.set(hasEnabledPowerModes, forKey: "powerModeUIFlag")
}
```

### Pattern: Logger Subsystem

- **Implementation**: always derive the subsystem from the fork config so log filtering works per-fork.

```swift
private let logger = Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "VoiceInkEngine")
```

### Pattern: Word Replacement & Vocabulary

- **When to use**: post-transcription text mutations from the user's custom dictionary.
- **Implementation**: `WordReplacementService` (`VoiceInk/Transcription/Processing/WordReplacementService.swift`) reads the `WordReplacement` SwiftData model and rewrites transcripts inside the pipeline. Replacements are sorted longest-first to handle overlapping patterns; matching uses `(?<![a-zA-Z0-9])…(?![a-zA-Z0-9])` lookarounds rather than `\b` so punctuation works correctly. Vocabulary terms (`VocabularyWord`) are surfaced to providers as a hint string.
- **Schema note**: vocabulary and replacements live in a separate `dictionary.store` (see `VoiceInk.swift:202-219`) which optionally syncs via CloudKit when not built with `LOCAL_BUILD`.

---

## Making Changes

### Before Starting

1. Check git status: `git status`.
2. Verify the project builds: `task build` (or `Cmd+B` in Xcode).
3. Run existing tests: `task test` (or `Cmd+U`).
4. Related files that often change together:
   - `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` + `VoiceInk/Recorder.swift` + `VoiceInk/CoreAudioRecorder.swift` (recording changes)
   - `VoiceInk/Services/AIEnhancement/AIService.swift` + `AIEnhancementService.swift` (AI features)
   - `VoiceInk/Views/` + `VoiceInk/Models/` (UI changes)
   - `VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift` + `FluidAudioModelManager.swift` (Parakeet/FluidAudio model changes)
   - `VoiceInk/Services/SelectedTextService.swift` + SelectedTextKit (text-selection extraction)
   - `VoiceInk/Transcription/Processing/WordReplacementService.swift` + `VoiceInk/Models/WordReplacement.swift` (custom-dictionary changes)

### During Development

- New services → follow patterns in `VoiceInk/Services/` (or `VoiceInk/Services/AIEnhancement/` for AI-tier services).
- New transcription providers → add to `VoiceInk/Transcription/Cloud/` or `VoiceInk/Transcription/Native/` and conform to the protocol in `VoiceInk/Transcription/Engine/TranscriptionService.swift`.
- New UI → follow conventions in `VoiceInk/Views/`.
- Profile with Instruments (Time Profiler, Allocations) for memory/CPU work.
- Security checklist:
  - ✓ API keys in Keychain via `KeychainService`/`APIKeyManager`
  - ✓ Permissions checked before use
  - ✓ User data stored under `AppConfig.shared.applicationSupportPath`
  - ✓ No sensitive data in logs (use `Obfuscator`)

### Testing Requirements

- Unit tests required for: all `*Service` classes and model logic.
- UI tests required for: main user flows, settings changes.
- Test file naming: `*Tests.swift` in `VoiceInkTests/`; UI tests in `VoiceInkUITests/`.
- Coverage target: 70% for new code.
- Run tests: `task test` (CLI) or `Cmd+U` (Xcode).

---

## Directory Structure

```
VoiceInk/                          (repo root)
├── BUILDING.md                    # canonical build guide
├── CLAUDE.md                      # this file
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md                # NB: PRs to upstream are not accepted
├── Fork.plist                     # fork configuration (gitignored)
├── Fork.plist.template            # configuration template
├── LICENSE
├── LocalBuild.xcconfig            # ad-hoc signing config for `make local` / `task build:local`
├── Makefile                       # alternative build interface (no `task` dependency)
├── README.md
├── Taskfile.yaml                  # primary build automation (47 tasks)
├── VoiceInk.xcodeproj/
├── VoiceInk/                      # main application source
│   ├── AppConfig.swift            # configuration singleton
│   ├── AppDefaults.swift          # UserDefaults registration
│   ├── AppDelegate.swift          # macOS app lifecycle
│   ├── ClipboardManager.swift
│   ├── CoreAudioRecorder.swift    # low-level audio capture
│   ├── CursorPaster.swift         # paste injection at cursor
│   ├── CustomSoundManager.swift   # custom start/stop sounds
│   ├── EmailSupport.swift
│   ├── HistoryWindowController.swift
│   ├── HotkeyManager.swift        # global hotkey wiring (KeyboardShortcuts)
│   ├── Info.plist
│   ├── MediaController.swift      # MediaRemoteAdapter integration (pause/resume music)
│   ├── MenuBarManager.swift
│   ├── MiniRecorderShortcutManager.swift
│   ├── PlaybackController.swift
│   ├── Recorder.swift             # high-level recording controller
│   ├── SoundManager.swift
│   ├── VoiceInk.entitlements      # full entitlements (signed builds)
│   ├── VoiceInk.local.entitlements# stripped entitlements (ad-hoc builds)
│   ├── VoiceInk.swift             # @main app entry, DI chain, SwiftData container
│   ├── WindowManager.swift
│   ├── AppIntents/                # Shortcuts.app integration
│   ├── Assets.xcassets/
│   ├── Models/                    # data models and view models
│   │   ├── Transcription.swift             # core SwiftData model
│   │   ├── VocabularyWord.swift            # custom-vocabulary entry
│   │   ├── WordReplacement.swift           # find/replace rule
│   │   ├── AudioFileQueueItem.swift
│   │   ├── AIPrompts.swift                 # AI prompt definitions
│   │   ├── PredefinedPrompts.swift
│   │   ├── PromptTemplates.swift
│   │   ├── CustomPrompt.swift
│   │   ├── LanguageDictionary.swift
│   │   ├── LicenseViewModel.swift
│   │   ├── TranscriptionModel.swift        # provider/model abstraction
│   │   └── TranscriptionModelRegistry.swift
│   ├── Notifications/             # in-app notification surface
│   │   ├── AppNotifications.swift          # central Notification.Name extension
│   │   ├── NotificationManager.swift
│   │   └── …
│   ├── PowerMode/                 # context-aware per-app config
│   │   ├── PowerModeView.swift
│   │   ├── PowerModeConfig.swift
│   │   ├── PowerModeManager.swift
│   │   ├── PowerModeShortcutManager.swift
│   │   └── ActiveWindowService.swift
│   ├── Resources/                 # bundled assets
│   ├── Services/                  # narrow business-logic services
│   │   ├── AIEnhancement/
│   │   │   ├── AIService.swift                 # AI provider management/selection
│   │   │   └── AIEnhancementService.swift      # text enhancement pipeline
│   │   ├── SelectedTextService.swift           # active-app selection extraction (SelectedTextKit)
│   │   ├── PolarService.swift                  # analytics (gated by EnableAnalytics)
│   │   ├── AnnouncementsService.swift          # gated by EnableAnnouncements
│   │   ├── APIKeyManager.swift / KeychainService.swift
│   │   ├── LicenseManager.swift
│   │   ├── AudioFileTranscriptionService.swift
│   │   ├── AudioFileTranscriptionManager.swift
│   │   ├── AutoLearnVocabularyService.swift
│   │   ├── CustomVocabularyService.swift / DictionaryService.swift
│   │   ├── ImportExportService.swift / VoiceInkCSVExportService.swift
│   │   ├── LastTranscriptionService.swift
│   │   ├── ModelPrewarmService.swift
│   │   ├── OllamaService.swift
│   │   ├── PromptDetectionService.swift
│   │   ├── ScreenCaptureService.swift
│   │   ├── Obfuscator.swift / LogExporter.swift / SystemInfoService.swift
│   │   ├── StreamingKeysMigration.swift
│   │   ├── SupportedMedia.swift / SystemArchitecture.swift
│   │   ├── TranscriptionAutoCleanupService.swift
│   │   ├── UserDefaultsManager.swift
│   │   ├── AudioDeviceManager.swift / AudioDeviceConfiguration.swift
│   │   └── WordCounter.swift / WordDiffEngine.swift
│   ├── Transcription/             # transcription pipeline & providers
│   │   ├── Engine/                # central engine + protocol surface
│   │   │   ├── VoiceInkEngine.swift            # central recording/transcription orchestrator
│   │   │   ├── VoiceInkEngine+Protocols.swift / VoiceInkEngineError.swift
│   │   │   ├── RecordingState.swift
│   │   │   ├── RecorderUIManager.swift         # owns mini/notch recorder UI lifecycle
│   │   │   ├── TranscriptionService.swift      # protocol all providers conform to
│   │   │   ├── TranscriptionServiceRegistry.swift
│   │   │   ├── TranscriptionPipeline.swift     # post-processing chain
│   │   │   ├── TranscriptionSession.swift
│   │   │   ├── TranscriptionModelManager.swift
│   │   │   └── AudioFileProcessor.swift
│   │   ├── Cloud/                 # cloud provider implementations
│   │   │   ├── CloudProvider.swift / CloudTranscriptionService.swift / CustomCloudModelManager.swift
│   │   │   ├── DeepgramProvider.swift, ElevenLabsProvider.swift, GeminiProvider.swift,
│   │   │   ├── GroqProvider.swift, MistralProvider.swift, SonioxProvider.swift,
│   │   │   ├── SpeechmaticsProvider.swift, XAIProvider.swift,
│   │   │   └── OpenAICompatibleTranscriptionService.swift
│   │   ├── Whisper/               # local whisper.cpp integration
│   │   │   ├── WhisperTranscriptionService.swift
│   │   │   ├── WhisperModelManager.swift / WhisperModelProvider.swift
│   │   │   ├── WhisperModelWarmupCoordinator.swift / WhisperPrompt.swift
│   │   │   ├── VADModelManager.swift
│   │   │   └── LibWhisper.swift                # whisper.cpp Swift wrapper
│   │   ├── FluidAudio/            # Parakeet (FluidAudio SDK) implementation
│   │   │   ├── FluidAudioTranscriptionService.swift
│   │   │   └── FluidAudioModelManager.swift
│   │   ├── Native/                # macOS native Speech framework
│   │   ├── Processing/            # post-processing services
│   │   │   └── WordReplacementService.swift
│   │   └── Streaming/             # streaming-mode transcription
│   └── Views/                     # SwiftUI views
│       ├── ContentView.swift                   # main window
│       ├── MenuBarView.swift / EnhancementSettingsView.swift / ModelSettingsView.swift
│       ├── KeyboardShortcutView.swift / PermissionsView.swift
│       ├── LicenseView.swift / LicenseManagementView.swift
│       ├── PromptEditorView.swift / PredefinedPromptsView.swift
│       ├── AudioTranscribeView.swift / AudioPlayerView.swift / AudioFileRow.swift
│       ├── TranscriptionResultView.swift / MetricsView.swift
│       ├── AI Models/                          # model selection / management UI
│       │   ├── ModelCardView.swift             # base card
│       │   ├── WhisperModelCardView.swift / CloudModelCardView.swift
│       │   ├── FluidAudioModelCardView.swift / NativeModelCardView.swift
│       │   ├── CustomModelCardView.swift / AddCustomModelView.swift
│       │   ├── APIKeyManagementView.swift / LanguageSelectionView.swift
│       │   └── ModelManagementView.swift
│       ├── Common/ Components/ Dictionary/ History/ Metrics/ Onboarding/ Recorder/ Settings/
├── VoiceInkTests/                 # unit tests
│   ├── ConfigurationTests.swift   # Fork.plist loading & defaults
│   ├── FeatureFlagTests.swift     # feature flag behavior
│   ├── IntegrationTests.swift     # end-to-end workflows
│   ├── MigrationTests.swift       # SwiftData migration & data upgrades
│   └── VoiceInkTests.swift        # base/helper tests
├── VoiceInkUITests/               # UI tests
│   ├── VoiceInkUITests.swift
│   └── VoiceInkUITestsLaunchTests.swift
├── docs/                          # long-form documentation
│   ├── API_REFERENCE.md
│   ├── ARCHITECTURE.md
│   ├── build.md
│   ├── FORK_GUIDE.md
│   ├── MIGRATION.md
│   └── PRIVACY_AUDIT.md
├── scripts/                       # build/automation scripts
│   ├── setup-environment.sh       # validate macOS/Xcode/git/disk
│   ├── setup-fork.sh              # interactive Fork.plist generator
│   ├── setup-project.sh           # full project setup orchestrator
│   ├── build-app.sh               # configurable build wrapper
│   ├── build-whisper.sh           # builds whisper.xcframework
│   ├── clean-build.sh             # tiered clean (normal / deep / full)
│   ├── create-release.sh          # release builds + DMG + notarization
│   ├── install.sh                 # install to /Applications
│   ├── reset-data.sh              # reset user data (all/data/transcriptions/models/preferences)
│   └── run-tests.sh               # test runner with coverage/filtering
├── specs/                         # in-flight feature specs
│   └── audio-visualization-enhancement.md
├── .github/                       # GitHub metadata
│   ├── ISSUE_TEMPLATE/{bug_report,feature_request}.md
│   └── PULL_REQUEST_TEMPLATE.md
└── .gitignore                     # includes Fork.plist
```

## File Naming Conventions

- Views: `*View.swift` (e.g. `SettingsView.swift`)
- Services: `*Service.swift` or `*Manager.swift`
- Transcription providers: `<Vendor>Provider.swift` or `<Vendor>TranscriptionService.swift`
- Models: singular nouns (e.g. `Transcription.swift`)
- ViewModels: `*ViewModel.swift`
- Tests: `*Tests.swift`

---

## Core APIs & Interfaces

### API: `VoiceInkEngine.toggleRecord(powerModeId:)`

- **Purpose**: start/stop the recording + transcription pipeline.
- **Signature**: `func toggleRecord(powerModeId: UUID? = nil) async`
- **File**: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift:80`
- **Usage**:

  ```swift
  @EnvironmentObject var engine: VoiceInkEngine
  Task { await engine.toggleRecord() }
  ```
- **Don't**: call without first ensuring microphone permission; don't bypass and drive the underlying `Recorder` directly.

### API: `AIEnhancementService.enhance(_:)`

- **Purpose**: enhance transcribed text with the currently selected AI prompt.
- **Signature**: `func enhance(_ text: String) async throws -> (String, TimeInterval, String?)` (returns enhanced text, duration, and resolved prompt name)
- **File**: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:368`
- **Usage**: prompt selection is via the service's `selectedPromptId` property — do not pass the prompt as an argument.
- **Don't**: call without an AI provider configured; don't confuse with `AIService` (which manages providers, not enhancement).

### API: `AIService`

- **Purpose**: provider selection and credential management for AI providers (Groq, Gemini, Claude, OpenAI-compatible, Ollama, etc.).
- **File**: `VoiceInk/Services/AIEnhancement/AIService.swift`
- **Usage pattern**: inject into `AIEnhancementService`; query for available providers and currently selected one. Don't call enhancement-style methods on it.

### API: `TranscriptionService` (protocol)

- **Purpose**: the abstraction every transcription backend conforms to.
- **Signature**: `func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String`
- **File**: `VoiceInk/Transcription/Engine/TranscriptionService.swift:5-13`
- **Usage**: implement for new providers, register with `TranscriptionServiceRegistry`.
- **Don't**: assume the audio file fits in memory — providers stream as needed.

### API: `FluidAudioTranscriptionService.loadModel(for:)`

- **Purpose**: load a specific FluidAudio (Parakeet) model variant.
- **Signature**: `func loadModel(for model: FluidAudioModel) async throws`
- **File**: `VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift:74`
- **Usage**:

  ```swift
  let service = FluidAudioTranscriptionService()
  try await service.loadModel(for: fluidAudioModel)
  let transcript = try await service.transcribe(audioURL: url, model: fluidAudioModel)
  ```
- **Don't**: call `transcribe` before `loadModel` — the service maintains an active-version state and switches/cleans up between variants.

### API: `FluidAudioModelManager.showFluidAudioModelInFinder(_:)`

- **Purpose**: open Finder to the cached FluidAudio model location.
- **Signature**: `func showFluidAudioModelInFinder(_ model: FluidAudioModel)`
- **File**: `VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift:102`

### API: `SelectedTextService.fetchSelectedText()`

- **Purpose**: read currently selected text from the active application.
- **Signature**: `static func fetchSelectedText() async -> String?`
- **File**: `VoiceInk/Services/SelectedTextService.swift`
- **Usage**:

  ```swift
  if let text = await SelectedTextService.fetchSelectedText() {
      // process selection
  }
  ```
- **Don't**: bypass and manipulate the clipboard directly — SelectedTextKit handles that for us.

---

## State Management

### State Patterns

- **Containers**: SwiftUI `@StateObject` + `ObservableObject`; injected app-wide via `.environmentObject(...)` from `VoiceInkApp.body`.
- **Structure**:
  - App-wide: `VoiceInkEngine`, `AIService`, `AIEnhancementService`, `WhisperModelManager`, `FluidAudioModelManager`, `TranscriptionModelManager`, `RecorderUIManager`, `HotkeyManager`, `MenuBarManager`, `UpdaterViewModel`, `ActiveWindowService`.
  - View-specific: local `@State` and `@StateObject`-owned view models.
  - Persistent: `@AppStorage` for primitives, SwiftData (`Transcription`, `VocabularyWord`, `WordReplacement`) for richer data.
- **Update patterns**: `@Published` properties trigger UI updates.
- **Side effects**: `Task { ... }` for async work spawned from sync contexts; `@MainActor` for UI mutations.

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

- **Error types**: custom enums conforming to `Error` (e.g. `VoiceInkEngineError`).
- **Strategy**: `do`/`try`/`catch` with provider-specific cases.
- **Logging**: `Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "Feature")`.
- **User feedback**: `NSAlert` for user-actionable errors; logger for system-level details.
- **Recovery**: retry with exponential backoff for transient network errors.

```swift
do {
    try await performOperation()
} catch NetworkError.timeout {
    // retry logic
} catch {
    logger.error("Operation failed: \(error.localizedDescription, privacy: .public)")
}
```

---

## Testing Patterns

### Test Structure

- **Setup**: `XCTestCase` with `setUp()` / `tearDown()`.
- **Mocking**: protocol-based dependency injection; e.g. swap `TranscriptionService` implementations.
- **Assertions**: `XCTAssert*`, `XCTestExpectation` for async, plus Swift Testing's `#expect` where adopted.
- **Locations**: `VoiceInkTests/` for unit tests, `VoiceInkUITests/` for UI tests.

### Test Categories

1. **Configuration Tests** (`ConfigurationTests.swift`) — Fork.plist loading, default values, feature-flag behavior.
2. **Feature Flag Tests** (`FeatureFlagTests.swift`) — conditional feature enabling, UI element visibility, service initialization.
3. **Integration Tests** (`IntegrationTests.swift`) — end-to-end workflows, service interactions, data persistence.
4. **Migration Tests** (`MigrationTests.swift`) — SwiftData schema migrations, data upgrades, backward compatibility.
5. **Base helpers** (`VoiceInkTests.swift`) — shared utilities.
6. **UI Tests** (`VoiceInkUITests/VoiceInkUITests.swift`, `VoiceInkUITestsLaunchTests.swift`) — main user flows.

### Running Tests

```bash
task test                  # all tests
task test:unit             # unit tests only
task test:ui               # UI tests only
task test:fork             # Fork configuration tests
task test:features         # feature-flag tests
task test:integration      # integration tests
task test:coverage         # with coverage report
task test:filter -- Pattern# matching pattern
task test:watch            # watch mode
```

---

## HOW TO: Add a New Transcription Provider

1. **Implement the protocol**:
   - For cloud providers, add to `VoiceInk/Transcription/Cloud/` (use `OpenAICompatibleTranscriptionService.swift` as a reference).
   - For native providers, add to `VoiceInk/Transcription/Native/`.
   - Conform to `TranscriptionService` (`VoiceInk/Transcription/Engine/TranscriptionService.swift`).
2. **Register the model**:
   - Add a `TranscriptionModel` definition in `VoiceInk/Models/TranscriptionModelRegistry.swift`.
   - Wire the new service into `TranscriptionServiceRegistry`.
3. **Add UI**:
   - Add a card in `VoiceInk/Views/AI Models/` (clone the closest existing `*ModelCardView.swift`).
   - Update `ModelManagementView` if listing/grouping needs to change.
4. **Test**:
   - Add a unit test for the service.
   - Add a UI test for the configuration flow if visible to the user.
5. **Document**: update `README.md` if the addition is user-facing.

---

## HOW TO: Create Your Own Fork

1. **Set up the fork**:

   ```bash
   ./scripts/setup-fork.sh        # interactive

   # …or manually:
   cp Fork.plist.template Fork.plist
   # edit Fork.plist with your configuration
   ```

2. **Add `Fork.plist` to Xcode**:
   - Open `VoiceInk.xcodeproj`.
   - Drag `Fork.plist` into the project navigator.
   - Confirm membership in the `VoiceInk` target.

3. **Configure features**:
   - Set feature flags in `Fork.plist`.
   - Configure URLs for any external services you want to enable.
   - Set bundle identifier prefix and support email.

4. **Build**:

   ```bash
   task build           # debug
   task release         # release
   ```

5. **Test fork-specific features**:

   ```bash
   task test:fork
   ```

---

## HOW TO: Configure Feature Flags

1. **Edit `Fork.plist`**:

   ```xml
   <key>EnableAutoUpdates</key>
   <true/>
   <key>ShowPurchaseOptions</key>
   <false/>
   ```

2. **Use in code**:

   ```swift
   if AppConfig.shared.enableLicenseValidation {
       // license logic
   }
   ```

3. **Available flags**:
   - `EnableAutoUpdates` — Sparkle auto-updates
   - `EnableLicenseValidation` — license checking
   - `EnableAnnouncements` — announcements service
   - `EnableAnalytics` — Polar analytics
   - `ShowPurchaseOptions` — purchase UI
   - `ShowCommunityLinks` — community/Discord links
   - `ShowDonationLink` — donation/tip-jar link

---

## HOW TO: Build and Install Locally

```bash
task setup           # one-time
task build           # debug
task release         # release
task install         # install to /Applications
task clean && task build   # clean rebuild

# Or, without `task`:
make                 # all (= setup + build)
make local           # ad-hoc-signed build to ~/Downloads
```

For ad-hoc-signed builds (no Apple Developer account), use `task build:local` or `make local` — both pick up `LocalBuild.xcconfig` and `VoiceInk.local.entitlements`.

---

## HOW TO: Fix a Bug

1. **Reproduce**: run from Xcode; enable verbose logging via `logger.debug()` in the suspect category.
2. **Debug**: Xcode breakpoints, Console.app for system logs, Instruments for performance issues.
3. **Fix**: minimal change; add a regression test; update affected docs if behavior changed.
4. **Test**: full test suite + manual exercise of affected flows.
5. **Verify**: no new warnings; performance unchanged.

---

## Performance & Optimization

- **Response time**: < 100ms for UI interactions.
- **Memory**: < 500MB typical, < 1GB peak.
- **Optimization patterns**: lazy model loading; background queues for heavy work; `ModelPrewarmService` warms the active model on wake from sleep (`PrewarmModelOnWake` UserDefault).
- **Profiling**: Instruments (Time Profiler, Allocations).
- **Bottlenecks**: model loading (cache in memory), large audio files (stream/chunk).

---

## Integration Points

### External Integrations

- **whisper.cpp**: local Whisper transcription via `whisper.xcframework` (built from `../whisper.cpp` in Taskfile, or `~/VoiceInk-Dependencies/whisper.cpp` in Makefile).
- **FluidAudio**: Parakeet ASR via the `FluidAudio` Swift package.
- **Cloud APIs**: OpenAI-compatible, Anthropic, Groq, Gemini, Mistral, Deepgram, ElevenLabs, Soniox, Speechmatics, xAI — all via REST.
- **macOS APIs**: AVFoundation (audio), ScreenCaptureKit (context), Accessibility (window detection).
- **SelectedTextKit**: text-selection extraction from active applications.
- **Sparkle**: auto-update framework — **optional**, gated by `EnableAutoUpdates`.
- **Keychain**: secure credential storage (`KeychainService`, `APIKeyManager`).
- **CloudKit**: optional sync for the dictionary store (vocabulary + replacements); disabled when built with `LOCAL_BUILD`.

### Optional Services (Controlled by Configuration)

- **License validation** — disabled by default (`EnableLicenseValidation`)
- **Analytics/Telemetry** — disabled by default (`EnableAnalytics`)
- **Announcements service** — disabled by default (`EnableAnnouncements`)
- **Auto-updates** — disabled by default (`EnableAutoUpdates`)

All external services are opt-in, controlled via `Fork.plist`.

---

## Known Issues & Gotchas

### Issue: Microphone permission denied silently
**Workaround**: check `AVCaptureDevice.authorizationStatus(for: .audio)` before recording.

### Issue: SwiftData migration fails on schema change
**Workaround**: implement proper `VersionedSchema` migrations; remember the dictionary store has its own schema.

### Issue: Memory spike during long recordings
**Workaround**: stream audio to disk; process in chunks; ensure model isn't reloaded mid-session.

### Issue: FluidAudio model version switching
**Explanation**: `FluidAudioTranscriptionService` maintains an active-version state and cleans up the previous model when switching variants.
**Solution**: always call `loadModel(for:)` before `transcribe(...)`. Don't assume models persist across calls.

### Issue: Power Mode persisting between recordings
**Explanation**: by default, Power Mode-applied configurations always reset between recordings. The user can opt into persistence via the **Persist Configured Preferences** toggle (UserDefault key `powerModePersistConfig`). Don't re-introduce the previous "auto-restore" semantics — they leaked configuration between sessions.

### Non-Obvious Requirements:

- App must work completely offline (local Whisper / FluidAudio / native models).
- Must respect system audio routing changes (`AudioDeviceManager`).
- Power Mode requires Accessibility permissions.
- Screen capture for context requires permission.
- **`Fork.plist` must be added to the Xcode project after creation** (it's gitignored, so a fresh clone won't include it in the bundle automatically).
- **Bundle identifier changes require a clean build.**
- **`VoiceInk.entitlements` uses dynamic bundle identifier via `$(PRODUCT_BUNDLE_IDENTIFIER)`.**
- **whisper.xcframework location depends on build system**: Taskfile expects `../whisper.cpp`; Makefile expects `~/VoiceInk-Dependencies/whisper.cpp/`. Don't mix the two without cleaning first.

### Historical Context:

- Originally used Core ML; switched to whisper.cpp for accuracy.
- Power Mode added due to user requests for automation.
- Multiple transcription backends for flexibility/reliability.
- **Forked to enable privacy-focused customization (2025).**
- All external communication made optional via configuration.

### Fork-Specific Gotchas:

**Issue: `Fork.plist` not found at runtime** → must be added to Xcode project membership for `VoiceInk` target so it ends up in the app bundle.

**Issue: Sparkle framework not found** → conditional compilation with `#if canImport(Sparkle)` handles forks that don't ship Sparkle.

**Issue: Feature flags not taking effect** → clean build after `Fork.plist` changes (`task clean && task build`).

**Issue: `LOCAL_BUILD` flag missing in Xcode-only build** → only `task build:local` and `make local` set the flag; building from Xcode directly without selecting the local config will not.

**Issue: `task build` (signed Debug/Release) fails with provisioning-profile errors about Push Notifications / iCloud capabilities** → `VoiceInk/VoiceInk.entitlements` declares `com.apple.developer.aps-environment` and `com.apple.developer.icloud-*`; the App ID `<BundleIdentifierPrefix>.VoiceInk` in your Apple Developer account must have **Push Notifications** and **iCloud (with a container `iCloud.<BundleIdentifierPrefix>.VoiceInk`)** enabled, and the provisioning profile regenerated. If you don't need CloudKit dictionary sync (e.g. all `Fork.plist` external services off), use `task build:local` / `make local` instead — `VoiceInk.local.entitlements` strips these capabilities and `LOCAL_BUILD` disables the CloudKit code path. Note: `scripts/build-app.sh` filters output by keyword and **hides these errors by default** — re-run with `./scripts/build-app.sh --verbose` to see the real cause.

**Issue: Build fails after renaming/moving the checkout directory (`error: There is no XCFramework found at '<old-path>/build/SourcePackages/artifacts/sparkle/...'`)** → SPM caches absolute paths in `build/SourcePackages/workspace-state.json`, `build/ModuleCache.noindex/`, and intermediate `*.DependencyStaticMetadataFileList` files. Fix: `rm -rf ./build ./.local-build` (both are gitignored derived-data paths). Same applies to the Makefile's `~/VoiceInk-Dependencies/` if you move that.

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

```xml
<!-- Only enable what you need -->
<key>EnableAutoUpdates</key>
<true/>

<key>SparkleUpdateURL</key>
<string>https://your-server.com/appcast.xml</string>
```

### Data Privacy Guarantees

1. **No hardcoded external URLs** — all URLs are configurable.
2. **No telemetry by default** — must explicitly enable.
3. **Local-first operation** — works fully offline.
4. **Transparent networking** — all network calls are user-initiated or explicitly configured.
5. **API keys in Keychain** — never stored in UserDefaults or in code.
6. **HTTP response cache disabled at launch** (`URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)` — see `VoiceInk.swift:42`) so API responses don't end up in `Cache.db`.

---

## Development Tips

### Swift/SwiftUI Best Practices

- Prefer `if let` / `guard let` over force unwrapping.
- Use `@MainActor` for UI updates.
- Leverage property wrappers (`@StateObject`, `@EnvironmentObject`, `@AppStorage`).
- Keep views small and composable.

### Common Pitfalls to Avoid

- Don't block main thread with transcription.
- Don't store sensitive data in UserDefaults.
- Don't assume permissions are granted.
- Don't ignore memory warnings.
- Don't call `transcribe` on a FluidAudio service before `loadModel`.
- Don't drive `Recorder` directly when `VoiceInkEngine` exists — go through the engine.

### Debugging Helpers

- Enable "Debug > Debug Workflow > View Debugging" in Xcode.
- Use Console.app for system-level logs (filter by `AppConfig.shared.loggerSubsystem`).
- Add `.border(Color.red)` to debug view layouts.
- `po` in LLDB for object inspection.

---

## Quick Reference

### Key Files

- App entry / DI: `VoiceInk/VoiceInk.swift`
- Recording / transcription engine: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`
- Recorder: `VoiceInk/Recorder.swift` + `VoiceInk/CoreAudioRecorder.swift`
- UI entry: `VoiceInk/Views/ContentView.swift`
- AI provider mgmt: `VoiceInk/Services/AIEnhancement/AIService.swift`
- AI enhancement: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- App defaults: `VoiceInk/AppDefaults.swift`
- Configuration: `VoiceInk/AppConfig.swift`
- Notifications: `VoiceInk/Notifications/AppNotifications.swift`

### Important UserDefaults Keys

(Registered defaults live in `VoiceInk/AppDefaults.swift`.)

- `CurrentTranscriptionModel` — currently selected provider/model
- `isAIEnhancementEnabled` — global enhancement toggle
- `RecorderType` — `mini` / `notch` / `standard`
- `IsTextFormattingEnabled`, `IsVADEnabled`, `RemoveFillerWords`, `AppendTrailingSpace`
- `IsTranscriptionCleanupEnabled`, `TranscriptionRetentionMinutes`, `IsAudioCleanupEnabled`, `AudioRetentionPeriod`
- `restoreClipboardAfterPaste`, `clipboardRestoreDelay`, `useAppleScriptPaste`
- `isSystemMuteEnabled`, `audioResumptionDelay`, `isPauseMediaEnabled`, `isSoundFeedbackEnabled`
- `IsMenuBarOnly`, `hasCompletedOnboarding`, `autoUpdateCheck`, `enableAnnouncements`
- `powerModePersistConfig` — opt-in persistence for Power Mode preferences (default `false`)
- `powerModeUIFlag` — bootstrapped on first launch from existing PowerMode configurations (`VoiceInk.swift:49-52`)
- `SkipShortEnhancement`, `ShortEnhancementWordThreshold`, `EnhancementTimeoutSeconds`, `EnhancementRetryOnTimeout`
- `PrewarmModelOnWake`, `SelectedLanguage`
- `isMiddleClickToggleEnabled`, `middleClickActivationDelay`

### Notification Names

Defined in `VoiceInk/Notifications/AppNotifications.swift`:

- `.transcriptionCreated`, `.transcriptionCompleted`, `.transcriptionDeleted`
- `.toggleMiniRecorder`, `.dismissMiniRecorder`
- `.didChangeModel`, `.aiProviderKeyChanged`, `.licenseStatusChanged`
- `.enhancementToggleChanged`, `.promptDidChange`, `.promptSelectionChanged`, `.languageDidChange`
- `.powerModeConfigurationApplied`
- `.openFileForTranscription`, `.audioDeviceSwitchRequired`, `.navigateToDestination`
- `.AppSettingsDidChange`

### Build Commands

**Using Taskfile (recommended):**

```bash
task setup
task build              # debug
task build:local        # ad-hoc signed
task build:open         # build + launch
task release            # release
task install            # install to /Applications
task clean              # clean artifacts
task test               # all tests
task test:unit          # unit tests only
task test:ui            # UI tests only
task test:fork          # fork config tests
task dev                # build + watch
task dev:xcode          # open in Xcode
```

**Using Make (alternative):**

```bash
make                    # setup + build
make whisper            # build whisper.xcframework
make build              # debug build
make local              # ad-hoc signed → ~/Downloads/VoiceInk.app
make run                # launch built app
make dev                # build + run
make clean              # clean
```

**Direct Xcode commands (last resort):**

```bash
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk build
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk
xcodebuild clean -project VoiceInk.xcodeproj -scheme VoiceInk
```

---

## Fork Maintenance

### Updating from Upstream

1. Add upstream remote (one-time):

   ```bash
   git remote add upstream https://github.com/Beingpax/VoiceInk.git
   ```

2. Fetch and merge:

   ```bash
   git fetch upstream
   git merge upstream/main
   ```

3. Resolve conflicts in `Fork.plist`, `AppConfig.swift`, and any feature-flag-gated UI carefully — the upstream may not be aware of forks' privacy-by-default posture.

### Managing Configuration Changes

- **`Fork.plist` changes**: always test feature flags after changes.
- **`AppConfig.swift` changes**: ensure backward compatibility (defaults must keep older Fork.plist files working).
- **Bundle ID changes**: require a clean build and may strand existing users' Application Support data under the old prefix.

### Testing Fork-Specific Features

```bash
task test:fork           # configuration loading
task test:features       # feature flags
task test:integration    # integration tests
```

---

## Remember

This codebase prioritizes:

1. **Privacy** — local-first, optional cloud, privacy-by-default configuration.
2. **Performance** — responsive UI, fast transcription.
3. **Reliability** — multiple fallback options across providers.
4. **User Experience** — simple, intuitive interface.
5. **Customizability** — fork-friendly architecture with configuration system.

When developing, always consider:

- Will this work offline?
- Is the user's data secure?
- Does this maintain backward compatibility?
- Is the performance impact acceptable?
- Are external services properly gated by configuration?
- Will this work for all fork configurations (and for ad-hoc-signed local builds)?

Focus on maintaining the existing patterns and architecture. The codebase is well-structured — follow the established conventions for consistency. The fork configuration system enables customization without code changes.
