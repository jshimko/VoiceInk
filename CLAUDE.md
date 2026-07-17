# VoiceInk Development Guide for AI Agents

> **Last verified**: 2026-07-17 against commit `81180df`

## Purpose

VoiceInk is a native macOS voice-to-text application that provides accurate, privacy-focused transcription with AI enhancement capabilities. This is a **configurable fork** with privacy-by-default settings, where all external communication is optional and controlled via configuration. This directory contains the complete Swift/SwiftUI application source code.

## Domain Context

Voice transcription and text processing application for macOS, featuring:

- Real-time voice recording and transcription (batch and streaming/realtime)
- Multiple transcription backends (local Whisper, FluidAudio Parakeet/Nemotron, native Apple Speech, plus 10 cloud providers)
- AI-powered text enhancement and formatting (cloud LLMs, local Ollama, local CLI tools)
- Voice **Assistant** mode — dictated conversations with an LLM, with follow-up turns
- Context-aware **Modes** for automatic per-app / per-URL / trigger-word configuration
- Flexible output delivery: paste at cursor, AI response in the recorder, or pipe to a custom shell command
- Productivity **Dashboard** with per-model usage/performance insights (backed by a dedicated stats store)
- Privacy-first design with 100% offline capability
- Custom vocabulary and word replacement post-processing
- Localized UI (English, German, Simplified Chinese via `Localizable.xcstrings`)
- **Fully configurable fork architecture** — customize branding, URLs, and features
- **Privacy-by-default** — all external services are opt-in via configuration

## Dependencies

- **Internal**: Core modules are self-contained within `VoiceInk/`.
- **Build Tools**:
  - Taskfile (build automation — `brew install go-task`) — recommended
  - Make (alternative, simpler — no extra install)
  - Xcode 15+ (Swift compiler and toolchain)
- **Swift Package dependencies** (resolved by Xcode/SPM):
  - whisper.xcframework (local Whisper transcription, built from `whisper.cpp` — local binary framework, not SPM)
  - FluidAudio (Parakeet + Nemotron ASR models)
  - Sparkle (auto-updates — **optional**, gated by `EnableAutoUpdates`)
  - LLMkit (Anthropic + OpenAI-compatible chat clients for AI enhancement/assistant)
  - swift-markdown-ui / MarkdownUI (markdown rendering)
  - MediaRemoteAdapter (media playback control)
  - LaunchAtLogin-Modern (startup management)
  - SelectedTextKit (text selection extraction from active apps; pulls in AXSwift, KeySender)
  - Zip, swift-atomics (utility dependencies)

Global hotkeys are handled by the in-repo `VoiceInk/Shortcuts/` subsystem (CGEvent taps + NSEvent monitors) — there is **no** third-party hotkey package. `ShortcutMigration` still reads the old `KeyboardShortcuts_*` UserDefaults keys one time to migrate legacy bindings.

## Dependents

This is the main application — no internal dependents.

---

## ⚠️ CRITICAL CONSTRAINTS

### NEVER Modify Without Coordination:

- **`VoiceInk/Transcription/Engine/VoiceInkEngine.swift`**: Central recording/transcription orchestrator — changes affect the entire recording pipeline
- **`VoiceInk/VoiceInk.swift`**: App initialization and dependency-injection chain — incorrect changes break startup; construction order is load-bearing (migrations run before model managers load)
- **`VoiceInk/Info.plist`**: App permissions — wrong values crash the app
- **SwiftData schema** (`Transcription`, `VocabularyWord`, `WordReplacement`, `SessionMetric` models): schema changes require migration code. Four models are split across **three stores** (`default.store`, `dictionary.store`, `stats.store` — see `VoiceInk.swift:217-263`); only the dictionary store has CloudKit configuration. Several properties carry `@Attribute(originalName: "powerMode...")` column renames (`Transcription.modeName`/`modeEmoji`, `SessionMetric.modeName`) — removing `originalName` breaks existing stores.
- **Migration code** (`OnboardingV2Migration.swift`, `Modes/ModeDataMigration.swift`, `Shortcuts/ShortcutMigration.swift`, `Services/StreamingKeysMigration.swift`, `Services/SessionMetricMigrationService.swift`): all are one-shot, flag-guarded, and read legacy key names on purpose — don't "clean up" legacy key references
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
- **Per-mode configuration**: Services should take runtime configuration structs (`TranscriptionRuntimeConfiguration`, `EnhancementRuntimeConfiguration`, `OutputRuntimeConfiguration` from `ModeRuntimeResolver`) rather than reading global UserDefaults directly — most behavior is now resolved per active mode.

### Performance Requirements:

- Transcription must start within 100ms of recording stop.
- UI must remain responsive during transcription.
- Memory usage should not exceed ~500MB during normal operation.

### Security Requirements:

- NEVER send audio data to cloud without explicit user consent.
- API keys must be stored in Keychain (`KeychainService.swift` / `APIKeyManager.swift`), not UserDefaults.
- Obfuscate sensitive data in logs (`Obfuscator.swift`).
- Validate all user input before processing.
- Custom-model connection tests are HTTPS-only (`CustomModelConnectionTester`).

---

## Architecture Overview

### High-Level Design Pattern

**MVVM + Service Layer + Engine Pipeline**

```
Views (SwiftUI) ─► EnvironmentObjects (VoiceInkEngine, *ModelManager, AIEnhancementService, RecordingShortcutManager, …)
                       │
                       ▼
         VoiceInkEngine ─► Recorder ─► TranscriptionPipeline ─► TranscriptionDelivery
                │                            │                        │
                │                            ▼                        ▼
                │              TranscriptionServiceRegistry     paste (CursorPaster) /
                │              Whisper / FluidAudio / Native /  AI respond (Assistant) /
                │              Cloud batch / Streaming          custom shell command
                │                            │
                ▼                            ▼
     ActiveWindowService (Modes)   Post-processing: OutputFilter →
     ModeRuntimeResolver           ParagraphFormatter → WordReplacement →
                │                  AI Enhancement (optional)
                ▼
     Models (SwiftData: Transcription | VocabularyWord + WordReplacement | SessionMetric)
```

`VoiceInkEngine` owns the recording lifecycle; the actual transcribe → post-process → enhance → save → deliver sequence lives in `TranscriptionPipeline`, and output handling in `TranscriptionDelivery`. Provider implementations are pluggable through `TranscriptionService` (batch) and `StreamingTranscriptionProvider` (realtime), selected via `TranscriptionModelManager` + `TranscriptionRealtimeSupport`.

### Key Design Decisions

1. **SwiftUI over AppKit**: declarative UI, better state management. Main window is a custom `HStack { AppSidebar; detail }` driven by `MainWindowNavigation.selectedView` (not `NavigationSplitView`).
2. **SwiftData over Core Data**: simpler API, Swift-native, type-safe; uses three stores — `default.store` (transcriptions), `dictionary.store` (vocabulary/replacements, optionally CloudKit-synced), `stats.store` (session metrics).
3. **Service + Engine layering**: `VoiceInkEngine` is the central orchestrator; individual `*Service` and `*Manager` classes are narrow and DI-injected.
4. **Pluggable transcription providers**: cloud providers conform to `CloudProvider` and register in `CloudProviderRegistry`; their models flow automatically into `TranscriptionModelRegistry`. Batch and streaming are separate protocol surfaces.
5. **Modes as the configuration layer**: per-mode settings (model, language, prompt, output mode, triggers) are resolved into runtime configuration structs by `ModeRuntimeResolver`; services consume the structs, not globals.
6. **Fork Configuration System**: enables customization without code changes, privacy-by-default.
7. **Conditional compilation**: optional features (Sparkle, CloudKit-syncing dictionary) without forcing dependencies; `LOCAL_BUILD` flag disables CloudKit for ad-hoc-signed builds.
8. **One-shot flag-guarded migrations**: every data-shape change ships with a UserDefaults-flag-guarded migration that reads legacy keys once and rewrites them (see the migration files listed in Critical Constraints).

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
task --list           # full list (49 tasks)
task setup            # full project setup (env check + whisper + project)
task build            # debug build
task build:open       # debug build + launch app
task build:local      # ad-hoc-signed build (no Apple Developer cert required)
task test             # run all tests
task release          # release build
task install          # build + install to /Applications
task clean            # clean build artifacts
task check            # quick health/verification checks
task run              # launch the built app
task dev              # build and watch for changes
task dev:xcode        # open project in Xcode
task doctor           # diagnose common issues
task info             # print project/build info
```

Task groups also exist for `setup:*` (`env`, `project`, `whisper`), `build:*` (`clean`, `debug`, `local`, `open`, `release`, `universal`), `test:*` (`unit`, `ui`, `coverage`, `filter`, `watch`, `fork`, `features`, `integration`), `clean:*` (`deep`, `full`, `whisper`), `release:*` (`dmg`, `install`, `notarize`, `version`), `reset:*` (`all`, `data`, `transcriptions`, `models`, `preferences`), `install:quick`, `docs:serve`, and CI helpers (`ci`, `ci:quick`).

The Taskfile expects `whisper.cpp` cloned as a sibling at `../whisper.cpp` (built into `whisper.xcframework`). Framework detection also probes `../build-apple/` and `~/VoiceInk-Dependencies/whisper.cpp/build-apple/` as fallbacks.

### 2. Makefile (alternative, simpler — no extra dependencies)

```bash
make           # all (= check + build)
make whisper   # clone/build whisper.xcframework
make build     # debug build
make local     # ad-hoc-signed build to ~/Downloads/VoiceInk.app (no cert)
make run       # launch built app
make dev       # build + run
make check     # environment health check (alias: healthcheck)
make clean     # remove build artifacts and dependencies
make help      # list targets
```

The Makefile manages dependencies in `~/.voiceink/whisper.cpp/` (different from the Taskfile's `../whisper.cpp` — the two systems are independent). `make clean` removes `~/.voiceink` entirely.

### 3. Local (unsigned) builds

`LocalBuild.xcconfig` + `VoiceInk/VoiceInk.local.entitlements` provide an ad-hoc-signed configuration that skips iCloud/CloudKit entitlements and APS push, so contributors without an Apple Developer account can build and run the app. Triggered via `task build:local` or `make local`. The build sets the `LOCAL_BUILD` Swift compilation flag, which disables CloudKit syncing on the dictionary store (`VoiceInk.swift:235-240`) and adjusts license/keychain behavior (`LicenseViewModel.swift`, `KeychainService.swift`).

### 4. Canonical reference

See `BUILDING.md` (project root) for the authoritative end-to-end build guide; `docs/build.md` may exist as a long-form reference.

### Build Configurations

- **Debug**: development build with debug symbols.
- **Release**: optimized production build.
- **Local**: ad-hoc-signed; no CloudKit, uses `VoiceInk.local.entitlements`.
- **Fork-customized**: any of the above with a custom `Fork.plist`.

---

## Established Patterns

### Pattern: Service Initialization & DI

- **When to use**: creating any new service that should be available across the app.
- **Implementation**: instantiate in `VoiceInkApp.init()`, wrap in `StateObject`, expose to views via `.environmentObject(...)`.
- **Example** (real fragment from `VoiceInk/VoiceInk.swift:100-108`):

```swift
let aiService = AIService()
_aiService = StateObject(wrappedValue: aiService)

let updaterViewModel = UpdaterViewModel()
_updaterViewModel = StateObject(wrappedValue: updaterViewModel)

let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
_enhancementService = StateObject(wrappedValue: enhancementService)
```

The full DI chain in `VoiceInk.swift:42-189` builds (in order): `AIService` → `UpdaterViewModel` → `AIEnhancementService` → model managers (`WhisperModelManager`, `FluidAudioModelManager`, `TranscriptionModelManager`) → `RecorderUIManager` → `VoiceInkEngine` → migrations + model loading (`StreamingKeysMigration.run()`, `refreshAllAvailableModels()`, `loadCurrentTranscriptionModel()` — **before** the StateObject assignments) → `RecordingShortcutManager` → `MenuBarManager` → `ActiveWindowService.shared` → `ModelPrewarmService` → session-metric migrations. Circular references are wired explicitly after construction: `recorderUIManager ⇄ engine` (`VoiceInk.swift:134-135`) and `appDelegate.menuBarManager` (`VoiceInk.swift:169`).

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
    await engine.toggleRecord(modeId: detectedModeId)
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
- **Example** (`VoiceInk/Models/LicenseViewModel.swift:51-60`):

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

### Pattern: Mode Runtime Resolution

- **When to use**: any behavior that can vary per mode (model, language, prompt, enhancement, output handling).
- **Implementation**: don't read global UserDefaults in the pipeline; resolve through `ModeRuntimeResolver` (`VoiceInk/Modes/ModeRuntimeConfiguration.swift`), which turns the active `ModeConfig` into `TranscriptionRuntimeConfiguration`, `EnhancementRuntimeConfiguration`, and `OutputRuntimeConfiguration` structs. Services accept these as parameters (e.g. `AIEnhancementService.enhance(_:configuration:contextSnapshot:)`).
- Modes store prompt selection as a UUID string (`ModeConfig.selectedPrompt`) resolved against `AIEnhancementService.allPrompts`; `repairModePromptSelections()` reconciles stale references.

### Pattern: One-Shot Flag-Guarded Migration

- **When to use**: any change to persisted data shape (UserDefaults keys, model names, shortcut storage, store layout).
- **Implementation**: read legacy key(s), rewrite into the new shape, set a one-shot UserDefaults guard flag, optionally delete the legacy keys. Run from a deterministic point in startup (`VoiceInk.swift` init, or lazily on first singleton access).
- **Examples**: `ModeDataMigration` (`powerModeConfigurationsV2` → `modeConfigurationsV2`), `ShortcutMigration` (`KeyboardShortcuts_*` → `Shortcut_*`), `StreamingKeysMigration` (renamed model names inside stored configs), `SessionMetricMigrationService` (backfills `stats.store` from historical `Transcription` rows), `OnboardingV2Migration` (prepares the v2 onboarding state).

### Pattern: Logger Subsystem

- **Implementation**: always derive the subsystem from the fork config so log filtering works per-fork.

```swift
private let logger = Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "VoiceInkEngine")
```

### Pattern: Word Replacement & Vocabulary

- **When to use**: post-transcription text mutations from the user's custom dictionary.
- **Implementation**: `WordReplacementService` (`VoiceInk/Transcription/Processing/WordReplacementService.swift`) reads the `WordReplacement` SwiftData model and rewrites transcripts inside the pipeline. Replacements are sorted longest-first to handle overlapping patterns; matching uses `(?<![a-zA-Z0-9])…(?![a-zA-Z0-9])` lookarounds rather than `\b` so punctuation works correctly, with a plain-substring fallback for non-spaced scripts (CJK/Thai). Vocabulary terms (`VocabularyWord`) are surfaced to providers as a hint string.
- **Schema note**: vocabulary and replacements live in the separate `dictionary.store` (see `VoiceInk.swift:234-246`), which optionally syncs via CloudKit when not built with `LOCAL_BUILD`.

---

## Making Changes

### Before Starting

1. Check git status: `git status`.
2. Verify the project builds: `task build` (or `Cmd+B` in Xcode).
3. Run existing tests: `task test` (or `Cmd+U`).
4. Related files that often change together:
   - `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` + `TranscriptionPipeline.swift` + `VoiceInk/Recorder.swift` + `VoiceInk/CoreAudioRecorder.swift` (recording changes)
   - `VoiceInk/Transcription/Engine/TranscriptionDelivery.swift` + `VoiceInk/Paste/CursorPaster.swift` + `CustomCommandDeliveryRunner.swift` (output delivery changes)
   - `VoiceInk/Services/AIEnhancement/AIService.swift` + `AIEnhancementService.swift` + `AIChatCompletionService.swift` (AI features)
   - `VoiceInk/Modes/ModeConfig.swift` + `ModeRuntimeConfiguration.swift` + `ModeValidator.swift` (mode changes — remember `ModeDataMigration`)
   - `VoiceInk/Shortcuts/*` (hotkey changes — `RecordingShortcutManager` owns the other shortcut managers)
   - `VoiceInk/Views/` + `VoiceInk/Models/` (UI changes)
   - `VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift` + `FluidAudioModelManager.swift` (Parakeet/Nemotron model changes)
   - `VoiceInk/Transcription/Streaming/*` + `TranscriptionRealtimeSupport.swift` (streaming changes)
   - `VoiceInk/Services/SelectedTextService.swift` + SelectedTextKit (text-selection extraction)
   - `VoiceInk/Transcription/Processing/WordReplacementService.swift` + `VoiceInk/Models/WordReplacement.swift` (custom-dictionary changes)

### During Development

- New services → follow patterns in `VoiceInk/Services/` (or `VoiceInk/Services/AIEnhancement/` for AI-tier services).
- New transcription providers → see "HOW TO: Add a New Transcription Provider" below.
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
├── Taskfile.yaml                  # primary build automation (49 tasks)
├── VoiceInk.xcodeproj/
├── VoiceInk/                      # main application source
│   ├── AppConfig.swift            # configuration singleton
│   ├── AppDefaults.swift          # UserDefaults registration
│   ├── AppDelegate.swift          # macOS app lifecycle, reopen/file-open routing
│   ├── CoreAudioRecorder.swift    # low-level audio capture
│   ├── CustomSoundManager.swift   # custom start/stop sound selection
│   ├── EmailSupport.swift
│   ├── HistoryWindowController.swift
│   ├── Info.plist
│   ├── InfoPlist.xcstrings        # localized Info.plist strings
│   ├── Localizable.xcstrings      # UI localization (en, de, zh-Hans)
│   ├── MediaController.swift      # MediaRemoteAdapter integration (pause/resume music)
│   ├── MenuBarManager.swift       # menu bar + activation policy (regular/accessory)
│   ├── OnboardingV2Migration.swift# prepares v2 onboarding state at startup
│   ├── PlaybackController.swift
│   ├── Recorder.swift             # high-level recording controller
│   ├── SoundManager.swift
│   ├── SoundPlaybackEngine.swift  # AVAudioPlayer-backed start/stop/esc sounds
│   ├── VoiceInk.entitlements      # full entitlements (signed builds)
│   ├── VoiceInk.local.entitlements# stripped entitlements (ad-hoc builds)
│   ├── VoiceInk.swift             # @main app entry, DI chain, SwiftData container (3 stores)
│   ├── WindowManager.swift        # main-window presentation, activation policy helpers
│   ├── AppIntents/                # Shortcuts.app integration
│   ├── Assets.xcassets/           # incl. provider-* logo imagesets
│   ├── Models/                    # data models and view models
│   │   ├── Transcription.swift             # core SwiftData model (default.store)
│   │   ├── VocabularyWord.swift            # custom-vocabulary entry (dictionary.store)
│   │   ├── WordReplacement.swift           # find/replace rule (dictionary.store)
│   │   ├── SessionMetric.swift             # per-session analytics (stats.store)
│   │   ├── AssistantSession.swift          # in-memory assistant chat state (NOT @Model)
│   │   ├── AudioFileQueueItem.swift
│   │   ├── AIPrompts.swift                 # static system-prompt templates
│   │   ├── PromptTemplates.swift           # seedable editable default prompts (fixed UUIDs)
│   │   ├── CustomPrompt.swift              # user-editable prompt (UserDefaults `customPrompts`)
│   │   ├── LanguageDictionary.swift
│   │   ├── LicenseViewModel.swift
│   │   ├── TranscriptionModel.swift        # provider/model abstraction (ModelProvider enum)
│   │   ├── TranscriptionModelRegistry.swift# static + provider-generated model list
│   │   └── TranscriptionRealtimeSupport.swift # streaming availability/required/enabled logic
│   ├── Modes/                     # context-aware per-app/URL/trigger-word configuration
│   │   ├── ModeConfig.swift                # ModeConfig struct + ModeManager singleton
│   │   ├── ModeRuntimeConfiguration.swift  # ModeRuntimeResolver → runtime config structs
│   │   ├── ModeDataMigration.swift         # legacy PowerMode → Modes migration
│   │   ├── ModeValidator.swift
│   │   ├── ModeTriggerWordDetectionService.swift
│   │   ├── ActiveWindowService.swift       # app/URL-based mode activation
│   │   ├── BrowserURLService.swift
│   │   ├── StarterModeFactory.swift / StarterModeTemplate.swift / StarterModePromptSeeder.swift
│   │   ├── CustomCommandTemplate.swift
│   │   ├── ModeView.swift + editor/form/trigger UI (Trigger*.swift, Mode*View.swift)
│   │   └── …
│   ├── Notifications/             # in-app notification surface
│   │   ├── AppNotifications.swift          # central Notification.Name extension
│   │   ├── NotificationManager.swift
│   │   └── …
│   ├── Paste/                     # output pasting
│   │   ├── ClipboardManager.swift
│   │   ├── CursorPaster.swift              # CGEvent / AppleScript paste + clipboard restore
│   │   └── PasteMethod.swift               # paste-method setting + legacy-key migration
│   ├── Resources/                 # bundled assets (models/, Sounds/)
│   ├── Services/                  # narrow business-logic services
│   │   ├── AIEnhancement/
│   │   │   ├── AIService.swift                 # AI provider selection + credentials (AIProvider enum)
│   │   │   ├── AIEnhancementService.swift      # text enhancement pipeline
│   │   │   ├── AIChatCompletionService.swift   # AIService.completeChat — shared LLM entry point (LLMkit)
│   │   │   ├── CustomAIProviderManager.swift   # user-defined OpenAI-compatible enhancement providers
│   │   │   ├── LocalCLIService.swift           # local shell command as enhancement provider
│   │   │   ├── AIEnhancementOutputFilter.swift
│   │   │   └── ReasoningConfig.swift
│   │   ├── AssistantChatService.swift          # assistant turns → LLM + Transcription persistence
│   │   ├── SelectedTextService.swift           # active-app selection extraction (SelectedTextKit)
│   │   ├── RecordingContextSnapshot.swift      # clipboard/selection/screen-OCR context capture
│   │   ├── SessionMetricRecorder.swift / SessionMetricMigrationService.swift
│   │   ├── BackupImporter.swift / BackupTypes.swift / ImportExportService.swift
│   │   ├── VoiceInkCSVExportService.swift
│   │   ├── PolarService.swift                  # analytics (gated by EnableAnalytics)
│   │   ├── AnnouncementsService.swift          # gated by EnableAnnouncements
│   │   ├── APIKeyManager.swift / KeychainService.swift
│   │   ├── LicenseManager.swift
│   │   ├── AudioFileTranscriptionService.swift / AudioFileTranscriptionManager.swift
│   │   ├── CustomVocabularyService.swift / DictionaryService.swift
│   │   ├── LastTranscriptionService.swift
│   │   ├── ModelPrewarmService.swift
│   │   ├── OllamaService.swift
│   │   ├── ScreenCaptureService.swift
│   │   ├── ShellCommandEnvironment.swift       # env/PATH for LocalCLI + custom-command delivery
│   │   ├── AppAppearancePreference.swift / AppLanguagePreference.swift
│   │   ├── EstimatedTokenCounter.swift
│   │   ├── Obfuscator.swift / LogExporter.swift / SystemInfoService.swift
│   │   ├── StreamingKeysMigration.swift        # renamed model/streaming-defaults migration
│   │   ├── SupportedMedia.swift / SystemArchitecture.swift
│   │   ├── TranscriptionAutoCleanupService.swift
│   │   ├── UserDefaultsManager.swift
│   │   ├── AudioDeviceManager.swift / AudioDeviceConfiguration.swift
│   │   └── WordCounter.swift
│   ├── Shortcuts/                 # in-repo global hotkey subsystem (replaces KeyboardShortcuts pkg)
│   │   ├── Shortcut.swift                  # key or modifier-only shortcut value type
│   │   ├── ShortcutAction.swift            # enum of bindable actions (incl. .mode(UUID))
│   │   ├── ShortcutStore.swift             # UserDefaults persistence (Shortcut_<name> + _cleared)
│   │   ├── ShortcutMonitor.swift           # CGEvent session tap (global capture/suppression)
│   │   ├── ShortcutRecorder.swift          # SwiftUI capture UI (local NSEvent monitor)
│   │   ├── ShortcutValidator.swift
│   │   ├── ShortcutMigration.swift         # migrates legacy KeyboardShortcuts_* storage
│   │   ├── RecordingShortcutManager.swift  # top-level owner; creates the two below
│   │   ├── ModeShortcutManager.swift       # per-mode hotkeys
│   │   └── RecorderPanelShortcutManager.swift # Esc / Option+1..0 while panel visible
│   ├── Transcription/             # transcription pipeline & providers
│   │   ├── Engine/                # central engine + protocol surface
│   │   │   ├── VoiceInkEngine.swift            # central recording/transcription orchestrator
│   │   │   ├── VoiceInkEngine+Assistant.swift  # assistant follow-up / response completion
│   │   │   ├── VoiceInkEngine+Protocols.swift / VoiceInkEngineError.swift
│   │   │   ├── RecordingState.swift
│   │   │   ├── RecorderUIManager.swift         # owns mini/notch recorder UI lifecycle
│   │   │   ├── TranscriptionService.swift      # batch protocol + TranscriptionRequestContext
│   │   │   ├── TranscriptionServiceRegistry.swift
│   │   │   ├── TranscriptionPipeline.swift     # transcribe → post-process → enhance → save → deliver
│   │   │   ├── TranscriptionDelivery.swift     # paste / respond / custom-command dispatch
│   │   │   ├── CustomCommandDeliveryRunner.swift # zsh -lc runner (stdin + VOICEINK_TRANSCRIPT)
│   │   │   ├── TranscriptionSession.swift
│   │   │   ├── TranscriptionModelManager.swift
│   │   │   └── AudioFileProcessor.swift
│   │   ├── Cloud/                 # cloud provider implementations (batch)
│   │   │   ├── CloudProvider.swift             # protocol + CloudProviderRegistry (10 providers)
│   │   │   ├── CloudTranscriptionService.swift / CustomCloudModelManager.swift
│   │   │   ├── CustomModelConnectionTester.swift
│   │   │   ├── AssemblyAIProvider.swift, CartesiaProvider.swift, DeepgramProvider.swift,
│   │   │   ├── ElevenLabsProvider.swift, GeminiProvider.swift, GroqProvider.swift,
│   │   │   ├── MistralProvider.swift, SonioxProvider.swift, SpeechmaticsProvider.swift,
│   │   │   ├── XAIProvider.swift
│   │   │   └── OpenAICompatibleTranscriptionService.swift  # custom (BYO endpoint) models only
│   │   ├── Streaming/             # realtime transcription
│   │   │   ├── StreamingTranscriptionProvider.swift # protocol + events + stop disposition
│   │   │   ├── StreamingTranscriptionService.swift  # lifecycle + provider selection
│   │   │   ├── AssemblyAI/Cartesia/Deepgram/ElevenLabs/Mistral/Soniox/Speechmatics/XAI StreamingProvider.swift
│   │   │   ├── FluidAudioStreamingProvider.swift / FluidAudioUnifiedStreamingProvider.swift
│   │   │   ├── FluidAudioNemotronStreamingProvider.swift
│   │   │   ├── PCMAudioConverter.swift / WordAgreementEngine.swift
│   │   ├── Whisper/               # local whisper.cpp integration
│   │   │   ├── WhisperTranscriptionService.swift
│   │   │   ├── WhisperModelManager.swift / WhisperModelProvider.swift
│   │   │   ├── WhisperModelWarmupCoordinator.swift / WhisperPrompt.swift
│   │   │   ├── VADModelManager.swift
│   │   │   └── LibWhisper.swift                # whisper.cpp Swift wrapper
│   │   ├── FluidAudio/            # Parakeet + Nemotron (FluidAudio SDK)
│   │   │   ├── FluidAudioTranscriptionService.swift
│   │   │   └── FluidAudioModelManager.swift
│   │   ├── Native/                # macOS native Speech framework
│   │   │   ├── NativeAppleTranscriptionService.swift
│   │   │   └── NativeAppleSpeechAssetManager.swift # macOS 26+ speech asset download/reservation
│   │   └── Processing/            # post-processing services
│   │       ├── WordReplacementService.swift
│   │       ├── ParagraphFormatter.swift        # NLTokenizer paragraph chunking
│   │       ├── FillerWordManager.swift
│   │       └── TranscriptionOutputFilter.swift
│   └── Views/                     # SwiftUI views
│       ├── ContentView.swift                   # main window: HStack { AppSidebar; detail }, ViewType, MainWindowNavigation
│       ├── DashboardView.swift / MenuBarView.swift / ShortcutPreviewView.swift
│       ├── PromptEditorView.swift
│       ├── AudioTranscribeView.swift / AudioPlayerView.swift / AudioFileRow.swift
│       ├── TranscriptionResultView.swift
│       ├── LicenseView.swift / LicenseManagementView.swift
│       ├── AI Models/                          # model/provider management UI
│       │   ├── ModelManagementView.swift / ModelSettingsPanel.swift
│       │   ├── Whisper/Cloud/FluidAudio/Native/Custom ModelCardView.swift
│       │   ├── ProviderCloudManagementView / ProviderLocalManagementView / ProviderDetailPanel / ProviderSharedViews
│       │   ├── CustomProviderManagementView.swift
│       │   └── APIKeyManagementView.swift / LanguageSelectionView.swift
│       ├── Sidebar/AppSidebar.swift            # sidebar nav (220pt, ViewType-driven)
│       ├── Dashboard/                          # stats/insights cards, charts, loaders (21 files)
│       ├── Onboarding/                         # v2 flow: OnboardingCoordinator + FlowController + PermissionController,
│       │                                       # 8 stages: permissions → microphone → model → api → experience
│       │                                       #           → contextAwareness → trust → license
│       ├── History/                            # incl. HistoryAnalysisPanelView, HistorySettingsPanel
│       ├── Settings/                           # SettingsView, AudioSetupView, cleanup/sounds/diagnostics/shortcuts
│       ├── Recorder/                           # mini + notch recorder panels/windows, visualizer
│       └── Common/ Components/ Dictionary/     # AppTheme, surfaces/controls, reusable rows, dictionary UI
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
├── .github/                       # GitHub metadata (no CI workflows)
│   ├── ISSUE_TEMPLATE/{bug_report,feature_request}.md
│   └── PULL_REQUEST_TEMPLATE.md
└── .gitignore                     # includes Fork.plist, build/, .local-build/
```

## File Naming Conventions

- Views: `*View.swift` (e.g. `SettingsView.swift`)
- Services: `*Service.swift` or `*Manager.swift`
- Transcription providers: `<Vendor>Provider.swift` (batch) or `<Vendor>StreamingProvider.swift` (realtime)
- Models: singular nouns (e.g. `Transcription.swift`)
- ViewModels: `*ViewModel.swift`
- Tests: `*Tests.swift`

---

## Core APIs & Interfaces

### API: `VoiceInkEngine.toggleRecord(modeId:isAssistantFollowUp:)`

- **Purpose**: start/stop the recording + transcription pipeline.
- **Signature**: `func toggleRecord(modeId: UUID? = nil, isAssistantFollowUp: Bool = false) async`
- **File**: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift:180`
- **Usage**:

  ```swift
  @EnvironmentObject var engine: VoiceInkEngine
  Task { await engine.toggleRecord() }
  ```
- On record start it applies the mode via `ActiveWindowService.shared.beginApplyingConfiguration(modeId:)` and preloads the selected Whisper/FluidAudio model. On stop, work is handed to `TranscriptionPipeline.run(...)`.
- **Don't**: call without first ensuring microphone permission; don't bypass and drive the underlying `Recorder` directly.

### API: `TranscriptionService` (protocol)

- **Purpose**: the abstraction every batch transcription backend conforms to.
- **Signature**: `func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String`
- **File**: `VoiceInk/Transcription/Engine/TranscriptionService.swift:25-35` (context struct at lines 3-21; convenience overload without `context` at 37-42)
- **Usage**: implement for new providers, register with `TranscriptionServiceRegistry`.
- **Don't**: assume the audio file fits in memory — providers stream as needed. Note `TranscriptionRequestContext.scoped(to:)` strips the transcription prompt for every provider except Whisper.

### API: `StreamingTranscriptionProvider` (protocol)

- **Purpose**: the abstraction for realtime/streaming backends.
- **File**: `VoiceInk/Transcription/Streaming/StreamingTranscriptionProvider.swift:45-63`
- **Surface**: `connect(model:language:)`, `sendAudioChunk(_:)` (16-bit 16kHz mono LE PCM), `commit()`, `disconnect()`, `transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>` (`.sessionStarted/.partial/.committed/.error`), and `stopDisposition` (`.finalizeStreaming` default, or `.useBatchFallback` to re-transcribe the whole file on stop).
- Streaming eligibility is decided by `TranscriptionRealtimeSupport` (`isAvailable`/`isRequired`/`isEnabled`); `StreamingTranscriptionService.createProvider(for:)` **fatal-errors** on unsupported models, so always gate on `TranscriptionServiceRegistry.shouldUseRealtimeTranscription(for:)`.

### API: `AIEnhancementService.enhance(_:configuration:contextSnapshot:)`

- **Purpose**: enhance transcribed text with the prompt/provider/model resolved for the active mode.
- **Signature**: `func enhance(_ text: String, configuration: EnhancementRuntimeConfiguration, contextSnapshot: RecordingContextSnapshot? = nil) async throws -> (String, TimeInterval, String?)` (returns enhanced text, duration, and resolved prompt name)
- **File**: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:428`
- **Usage**: build the configuration via `ModeRuntimeResolver.currentEnhancementConfiguration(...)` — prompt selection lives on the mode (`ModeConfig.selectedPrompt` UUID string), not on the service.
- **Don't**: call without checking `isConfigured(for:)`; don't confuse with `AIService` (which manages providers, not enhancement).

### API: `AIService` + `AIService.completeChat(...)`

- **Purpose**: provider selection and credential management for AI providers, plus the shared chat-completion entry point.
- **Files**: `VoiceInk/Services/AIEnhancement/AIService.swift` (the `AIProvider` enum at line 4 lists 15 providers: Cerebras, Groq, Gemini, Anthropic, OpenAI, OpenRouter, Mistral, ElevenLabs, Deepgram, Soniox, Speechmatics, AssemblyAI, Ollama, Local CLI, Custom); `AIChatCompletionService.swift` adds `completeChat(provider:modelName:messages:systemPrompt:timeout:)` as an extension — it dispatches to LLMkit's Anthropic/OpenAI clients, Ollama, or the local CLI.
- **Note**: `supportsEnhancement` is false for the STT-only providers (ElevenLabs, Deepgram, Soniox, Speechmatics, AssemblyAI). `requiresAPIKey` is false for Ollama and Local CLI. User-defined OpenAI-compatible enhancement providers live in `CustomAIProviderManager` (UserDefaults `customAIProviders` + per-provider Keychain keys).

### API: `ModeManager` / `ModeRuntimeResolver`

- **Purpose**: the Modes system's manager singleton and runtime resolution.
- **Files**: `ModeManager` at `VoiceInk/Modes/ModeConfig.swift:273` (`@Published configurations`, `activeConfiguration`, app/URL/trigger-word lookups; persists JSON to UserDefaults `modeConfigurationsV2` + `activeConfigurationId`); `ModeRuntimeResolver` in `VoiceInk/Modes/ModeRuntimeConfiguration.swift`.
- **Usage**: reached via `ModeManager.shared` (not injected). Trigger-word selection during transcription goes through `VoiceInkEngine.selectTriggerWordModeIfNeeded(for:)`.
- **Don't**: bypass `ModeValidator` when saving; don't construct starter modes by hand (use `StarterModeFactory` — starter modes have fixed UUIDs `10000000-0000-0000-0000-00000000000{1..5}`).

### API: `TranscriptionDelivery.deliver(_:actions:)`

- **Purpose**: route the finished transcript to its output.
- **File**: `VoiceInk/Transcription/Engine/TranscriptionDelivery.swift:25`
- **Behavior**: branches on the mode's `OutputRuntimeConfiguration.outputMode` — `.paste` (via `CursorPaster`, honoring `AppendTrailingSpace` and optional auto-send), `.respond` (assistant reply shown in the recorder), `.customCommand` (via `CustomCommandDeliveryRunner`: `/bin/zsh -lc`, transcript on stdin **and** in `$VOICEINK_TRANSCRIPT`, 10s timeout with process-tree kill; non-zero exit is an error and nothing is pasted).

### API: `FluidAudioTranscriptionService.loadModel(for:)`

- **Purpose**: load a specific FluidAudio model variant.
- **Signature**: `func loadModel(for model: FluidAudioModel) async throws`
- **File**: `VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift:124`
- **Variants** (per `TranscriptionModelRegistry`): Parakeet V2/V3 (`parakeet-tdt-0.6b-v2/-v3`), Parakeet Unified (`parakeet-unified-0.6b`), Nemotron Latin/Multilingual (`nemotron-latin-0.6b`, `nemotron-multilingual-0.6b`).
- **Note**: for Nemotron `loadModel` is a deliberate no-op — Nemotron loads lazily inside `transcribe` (batch) or via its streaming manager, and **requires** realtime mode (`FluidAudioModelManager.requiresRealtime(named:)`). `transcribe` self-heals by ensuring models are loaded, so `loadModel` is a preload optimization for the Parakeet paths.

### API: `FluidAudioModelManager.showFluidAudioModelInFinder(_:)`

- **Purpose**: open Finder to the cached FluidAudio model location.
- **Signature**: `func showFluidAudioModelInFinder(_ model: FluidAudioModel)`
- **File**: `VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift:314`

### API: `SelectedTextService.fetchSelectedText()`

- **Purpose**: read currently selected text from the active application.
- **Signature**: `static func fetchSelectedText() async -> String?`
- **File**: `VoiceInk/Services/SelectedTextService.swift:16`
- **Don't**: bypass and manipulate the clipboard directly — SelectedTextKit handles that for us.

---

## State Management

### State Patterns

- **Containers**: SwiftUI `@StateObject` + `ObservableObject`; injected app-wide via `.environmentObject(...)` from `VoiceInkApp.body`.
- **Structure**:
  - App-wide (injected into `ContentView` and `MenuBarView`): `VoiceInkEngine`, `AIService`, `AIEnhancementService`, `WhisperModelManager`, `FluidAudioModelManager`, `TranscriptionModelManager`, `RecorderUIManager`, `RecordingShortcutManager`, `MenuBarManager`, `UpdaterViewModel`, `MainWindowNavigation`, plus `ModelPrewarmService` and `ActiveWindowService` held as StateObjects.
  - Singletons reached directly (not injected): `ModeManager.shared`, `ActiveWindowService.shared`, `WindowManager`, `CustomAIProviderManager.shared`, `APIKeyManager.shared`, `KeychainService.shared`.
  - View-specific: local `@State` and `@StateObject`-owned view models.
  - Persistent: `@AppStorage` for primitives, SwiftData (`Transcription`, `VocabularyWord`, `WordReplacement`, `SessionMetric`) for richer data; modes/prompts/shortcuts as JSON blobs in UserDefaults.
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

- **Error types**: custom enums conforming to `Error` (e.g. `VoiceInkEngineError`, `EnhancementError`, `CustomCommandDeliveryError`, `StreamingTranscriptionError`).
- **Strategy**: `do`/`try`/`catch` with provider-specific cases.
- **Logging**: `Logger(subsystem: AppConfig.shared.loggerSubsystem, category: "Feature")`.
- **User feedback**: `NSAlert` / `NotificationManager` for user-actionable errors; logger for system-level details.
- **Recovery**: retry with exponential backoff for transient network errors (see `AIEnhancementService.makeRequestWithRetry`); enhancement timeout behavior is governed by `EnhancementTimeoutSeconds` / `EnhancementRetryOnTimeout`.

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

1. **Cloud provider (batch and/or streaming)**:
   - Create `<Vendor>Provider.swift` in `VoiceInk/Transcription/Cloud/` conforming to `CloudProvider` (`Cloud/CloudProvider.swift:4-18`): declare `modelProvider`, `providerKey`, `languageCodes`, `models`, and implement `transcribe(...)` and/or `makeStreamingProvider(modelContext:)`. Set `isStreamingOnly = true` if there is no batch endpoint (see `CartesiaProvider`).
   - For streaming, add `<Vendor>StreamingProvider.swift` in `VoiceInk/Transcription/Streaming/` conforming to `StreamingTranscriptionProvider`.
   - Register in `CloudProviderRegistry.allProviders` (`Cloud/CloudProvider.swift:32-44`) — the provider's `models` then flow automatically into `TranscriptionModelRegistry.predefinedModels`.
   - Add a case to the `ModelProvider` enum in `VoiceInk/Models/TranscriptionModel.swift` and a Keychain mapping in `APIKeyManager.providerToKeychainKey`.
2. **Local/native providers**: add to `VoiceInk/Transcription/Native/` (or a new directory) conforming to `TranscriptionService`, wire into `TranscriptionServiceRegistry`, and add model entries to `TranscriptionModelRegistry.predefinedModels`.
3. **Add UI**: provider logo asset (`provider-*` imageset), and card/detail updates under `VoiceInk/Views/AI Models/` if listing/grouping needs to change.
4. **Test**: unit test for the service; UI test for the configuration flow if user-visible.
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
make                 # all (= check + build)
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
- **Optimization patterns**: lazy model loading; background queues for heavy work; `ModelPrewarmService` warms the active model on wake from sleep (`PrewarmModelOnWake` UserDefault); `WhisperModelWarmupCoordinator` transcribes a bundled warmup sample so the first real transcription isn't cold; `VoiceInkEngine` preloads the selected model during recording start.
- **Profiling**: Instruments (Time Profiler, Allocations).
- **Bottlenecks**: model loading (cache in memory), large audio files (stream/chunk).

---

## Integration Points

### External Integrations

- **whisper.cpp**: local Whisper transcription via `whisper.xcframework` (built from `../whisper.cpp` in Taskfile, or `~/.voiceink/whisper.cpp` in Makefile).
- **FluidAudio**: Parakeet (V2/V3/Unified) + Nemotron (Latin/Multilingual) ASR via the `FluidAudio` Swift package; Nemotron is streaming-only.
- **LLMkit**: Anthropic and OpenAI-compatible chat clients for enhancement/assistant.
- **Cloud STT APIs**: Groq, ElevenLabs, Deepgram, Mistral, Gemini, Soniox, Speechmatics, AssemblyAI, xAI, Cartesia (streaming-only) — via REST/WebSocket; plus BYO OpenAI-compatible endpoints (`OpenAICompatibleTranscriptionService`).
- **AI enhancement providers**: Cerebras, Groq, Gemini, Anthropic, OpenAI, OpenRouter, Mistral, Ollama (local), Local CLI (local shell command), custom OpenAI-compatible.
- **macOS APIs**: AVFoundation (audio), ScreenCaptureKit (context), Accessibility (window detection, CGEvent taps for shortcuts, paste injection), Apple Speech (`SpeechTranscriber`/`AssetInventory` on macOS 26+).
- **SelectedTextKit**: text-selection extraction from active applications.
- **Sparkle**: auto-update framework — **optional**, gated by `EnableAutoUpdates`.
- **Keychain**: secure credential storage (`KeychainService`, `APIKeyManager` — per-provider, per-custom-model, and per-custom-AI-provider keys).
- **CloudKit**: optional sync for the dictionary store (vocabulary + replacements); disabled when built with `LOCAL_BUILD`. The transcription and stats stores never sync.

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
**Workaround**: implement proper `VersionedSchema` migrations; remember there are **three** stores (`default`, `dictionary`, `stats`) with separate schemas, and several properties use `@Attribute(originalName: "powerMode...")` — the DB columns keep old names while Swift properties were renamed. Never drop the `originalName`.

### Issue: Memory spike during long recordings
**Workaround**: stream audio to disk; process in chunks; ensure model isn't reloaded mid-session.

### Issue: FluidAudio model loading semantics vary by variant
**Explanation**: `loadModel(for:)` preloads classic Parakeet and Parakeet Unified models, but is a **no-op for Nemotron** (which loads lazily in `transcribe` or via its streaming manager). `transcribe` self-heals if models aren't loaded. Nemotron models **require** realtime mode.
**Solution**: preload via `loadModel(for:)` where latency matters; never assume Nemotron is loadable outside a transcription/streaming session.

### Issue: Streaming must be gated before provider creation
**Explanation**: `StreamingTranscriptionService.createProvider(for:)` calls `fatalError` for unsupported models.
**Solution**: always check `TranscriptionServiceRegistry.shouldUseRealtimeTranscription(for:)` (backed by `TranscriptionRealtimeSupport`) first. Note Cartesia is streaming-only (`isStreamingOnly`), and a provider can return `.useBatchFallback` from `stopDisposition`, triggering a full-file batch re-transcription on stop.

### Issue: FluidAudio streaming drops trailing words/punctuation
**Explanation**: local FluidAudio paths append **1 second of trailing silence** before finalizing so end-of-utterance punctuation is captured (in `FluidAudioTranscriptionService` and `FluidAudioStreamingProvider`). This padding is load-bearing — don't remove it.

### Issue: Legacy "powerMode" identifiers still appear in code
**Explanation**: the Power Mode feature was renamed to **Modes**, but migration code intentionally still reads legacy keys (`powerModeConfigurationsV2`, `Shortcut_powerMode_<uuid>`, `KeyboardShortcuts_*`, `selectedHotkey1/2`, `hotkeyMode1/2`), backup import maps `powerModeConfigs`→`modeConfigs`, and SwiftData columns keep `powerMode*` original names.
**Solution**: don't "clean up" these references; they are one-shot migration reads and storage-compat shims.

### Issue: `.modeConfigurationApplied` notification is defined but unused
**Explanation**: `AppNotifications.swift` defines it, but nothing posts or observes it. The live mode notifications are `.modeConfigurationsDidChange` and `.modeShortcutAvailabilityDidChange`.

### Issue: Onboarding v2 preparation wipes mode/shortcut storage
**Explanation**: `OnboardingV2Migration.prepareIfNeeded()` (run at startup) removes existing mode configurations and shortcut storage for users who have **not** completed v2 onboarding (guarded by `hasPreparedOnboardingV2`). Starter modes are installed from onboarding (`StarterModeFactory`), not at app launch.
**Solution**: when testing onboarding flows, expect mode/shortcut state to reset; don't set `hasCompletedOnboardingV2` manually without understanding this.

### Issue: Shortcut system needs Accessibility permission for multiple event taps
**Explanation**: three independent `ShortcutMonitor` CGEvent taps can run simultaneously (recording/global, per-mode, recorder-panel). Each requires Accessibility trust; `RecordingShortcutManager.init` arms monitoring after a deliberate 100ms delay, and its construction is what triggers legacy shortcut migration.

### Issue: Custom command output mode failures look like "nothing happened"
**Explanation**: `.customCommand` delivery runs `/bin/zsh -lc <command>` with the transcript on stdin and in `$VOICEINK_TRANSCRIPT`, a 10s timeout (SIGTERM→SIGKILL of the process tree), and treats non-zero exit as an error — nothing is pasted on failure.
**Solution**: check the logs / `NotificationManager` surface; make custom commands exit 0 and finish within 10 seconds.

### Issue: Custom cloud uploads stall behind VPNs
**Explanation**: `OpenAICompatibleTranscriptionService` deliberately uses an ephemeral `URLSession` per request to avoid HTTP/3/QUIC upload blackholes behind VPNs (e.g. GlobalProtect). Keep that behavior when touching upload code.

### Non-Obvious Requirements:

- App must work completely offline (local Whisper / FluidAudio / native models).
- Must respect system audio routing changes (`AudioDeviceManager`); loopback channels are excluded from dictation input.
- Modes' app/URL triggers require Accessibility permissions; browser-URL triggers read the frontmost browser via `BrowserURLService`.
- Screen capture for context requires permission (`RecordingContextSnapshot` captures clipboard/selection/screen OCR as enhancement context).
- Native Apple Speech on macOS 26+ manages per-locale model assets with a **reservation limit** — `NativeAppleSpeechAssetManager` may need to release one locale to install another.
- **`Fork.plist` must be added to the Xcode project after creation** (it's gitignored, so a fresh clone won't include it in the bundle automatically).
- **Bundle identifier changes require a clean build.**
- **`VoiceInk.entitlements` uses dynamic bundle identifier via `$(PRODUCT_BUNDLE_IDENTIFIER)`.**
- **whisper.xcframework location depends on build system**: Taskfile expects `../whisper.cpp`; Makefile expects `~/.voiceink/whisper.cpp/`. Don't mix the two without cleaning first.

### Historical Context:

- Originally used Core ML; switched to whisper.cpp for accuracy.
- "Power Mode" evolved into the Modes system (per-app/URL/trigger-word configuration with per-mode output handling); the old `KeyboardShortcuts` package was replaced by the in-repo `Shortcuts/` subsystem at the same time.
- Trigger words originally selected prompts; they now select modes.
- Multiple transcription backends for flexibility/reliability.
- **Forked to enable privacy-focused customization (2025).**
- All external communication made optional via configuration.
- VoiceInk 2.0 shipped the v2 onboarding, Dashboard, Assistant, and localization.

### Fork-Specific Gotchas:

**Issue: `Fork.plist` not found at runtime** → must be added to Xcode project membership for `VoiceInk` target so it ends up in the app bundle.

**Issue: Sparkle framework not found** → conditional compilation with `#if canImport(Sparkle)` handles forks that don't ship Sparkle.

**Issue: Feature flags not taking effect** → clean build after `Fork.plist` changes (`task clean && task build`).

**Issue: `LOCAL_BUILD` flag missing in Xcode-only build** → only `task build:local` and `make local` set the flag; building from Xcode directly without selecting the local config will not.

**Issue: `task build` (signed Debug/Release) fails with provisioning-profile errors about Push Notifications / iCloud capabilities** → `VoiceInk/VoiceInk.entitlements` declares `com.apple.developer.aps-environment` and `com.apple.developer.icloud-*`; the App ID `<BundleIdentifierPrefix>.VoiceInk` in your Apple Developer account must have **Push Notifications** and **iCloud (with a container `iCloud.<BundleIdentifierPrefix>.VoiceInk`)** enabled, and the provisioning profile regenerated. If you don't need CloudKit dictionary sync (e.g. all `Fork.plist` external services off), use `task build:local` / `make local` instead — `VoiceInk.local.entitlements` strips these capabilities and `LOCAL_BUILD` disables the CloudKit code path. Note: `scripts/build-app.sh` filters output by keyword and **hides these errors by default** — re-run with `./scripts/build-app.sh --verbose` to see the real cause.

**Issue: Build fails after renaming/moving the checkout directory (`error: There is no XCFramework found at '<old-path>/build/SourcePackages/artifacts/sparkle/...'`)** → SPM caches absolute paths in `build/SourcePackages/workspace-state.json`, `build/ModuleCache.noindex/`, and intermediate `*.DependencyStaticMetadataFileList` files. Fix: `rm -rf ./build ./.local-build` (both are gitignored derived-data paths). Same applies to the Makefile's `~/.voiceink/` if you move that.

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
6. **HTTP response cache disabled at launch** (`URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)` — see `VoiceInk.swift:44`) so API responses don't end up in `Cache.db`.
7. **Session metrics stay local** — `stats.store` never syncs.

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
- Don't create a streaming provider for a model without gating on `shouldUseRealtimeTranscription` (it's a `fatalError`).
- Don't drive `Recorder` directly when `VoiceInkEngine` exists — go through the engine.
- Don't read global UserDefaults for behavior that Modes can override — use the runtime configuration structs.
- Don't remove `@Attribute(originalName:)` annotations or legacy-key migration reads.

### Debugging Helpers

- Enable "Debug > Debug Workflow > View Debugging" in Xcode.
- Use Console.app for system-level logs (filter by `AppConfig.shared.loggerSubsystem`; window-presentation diagnostics use the `MenuBarWindowFlow` category).
- Add `.border(Color.red)` to debug view layouts.
- `po` in LLDB for object inspection.

---

## Quick Reference

### Key Files

- App entry / DI: `VoiceInk/VoiceInk.swift`
- Recording / transcription engine: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`
- Pipeline / delivery: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`, `TranscriptionDelivery.swift`
- Recorder: `VoiceInk/Recorder.swift` + `VoiceInk/CoreAudioRecorder.swift`
- UI entry: `VoiceInk/Views/ContentView.swift` (+ `Views/Sidebar/AppSidebar.swift`)
- Modes: `VoiceInk/Modes/ModeConfig.swift` (ModeManager) + `ModeRuntimeConfiguration.swift`
- Shortcuts: `VoiceInk/Shortcuts/RecordingShortcutManager.swift`
- AI provider mgmt: `VoiceInk/Services/AIEnhancement/AIService.swift`
- AI enhancement: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- App defaults: `VoiceInk/AppDefaults.swift`
- Configuration: `VoiceInk/AppConfig.swift`
- Notifications: `VoiceInk/Notifications/AppNotifications.swift`

### Important UserDefaults Keys

Registered defaults live in `VoiceInk/AppDefaults.swift` (31 keys):

- Onboarding/general: `hasCompletedOnboardingV2`, `hasPreparedOnboardingV2`, `enableAnnouncements`
- Clipboard/paste: `restoreClipboardAfterPaste`, `clipboardRestoreDelay`, `useAppleScriptPaste` (legacy — superseded by `pasteMethod` via `PasteMethod.migrateLegacyUserDefaultIfNeeded()`)
- Audio/media: `isSystemMuteEnabled`, `audioResumptionDelay`, `isPauseMediaEnabled`, per-sound-type built-in sound keys (`CustomSoundManager`)
- Recording/transcription: `IsTextFormattingEnabled`, `IsVADEnabled`, `SelectedLanguage`, `AppendTrailingSpace`, `RecorderType` (`mini`/`notch`/`standard`), `ShowLiveTranscript`
- Cleanup: `IsTranscriptionCleanupEnabled`, `TranscriptionRetentionMinutes`, `IsAudioCleanupEnabled`, `AudioRetentionPeriod`
- UI: `IsMenuBarOnly`, `AppAppearancePreference`, `AppLanguagePreference`
- Shortcuts: `isMiddleClickToggleEnabled`, `middleClickActivationDelay`
- Enhancement: `SkipShortEnhancement`, `ShortEnhancementWordThreshold`, `EnhancementTimeoutSeconds`, `EnhancementRetryOnTimeout`
- Model: `PrewarmModelOnWake`

Important unregistered keys:

- `CurrentTranscriptionModel` — currently selected provider/model
- `selectedAIProvider` — selected AI enhancement provider
- `customPrompts` — JSON-encoded `[CustomPrompt]`
- `customAIProviders` — JSON-encoded custom enhancement providers
- `modeConfigurationsV2` / `activeConfigurationId` — JSON-encoded `[ModeConfig]` + active mode UUID
- `Shortcut_<action>` (+ `Shortcut_<action>_cleared`) — per-action shortcut blobs; per-mode is `Shortcut_mode_<uuid>`
- `primaryRecordingShortcut` / `secondaryRecordingShortcut` (+ `...ShortcutMode` — toggle/pushToTalk/hybrid)
- `pasteMethod` — `default` (CGEvent) or `appleScript`
- One-shot migration flags: `HasCompletedStatsMigration`, `HasCompletedStatsTokenBackfillV3`, `streaming-keys-migrated`, `Shortcut_Legacy*Migrated`
- `isAIEnhancementEnabled` — legacy global read only as a fallback during mode migration/resolution

### Notification Names

Defined in `VoiceInk/Notifications/AppNotifications.swift`:

- Transcriptions: `.transcriptionCreated`, `.transcriptionCompleted`, `.transcriptionDeleted`, `.sessionMetricsDidChange`
- Recorder panel: `.toggleRecorderPanel`, `.dismissRecorderPanel`
- Models/providers: `.didChangeModel`, `.aiProviderKeyChanged`
- License: `.licenseStatusChanged`, `.licenseCelebrationRequested`
- Modes: `.modeConfigurationsDidChange`, `.modeShortcutAvailabilityDidChange` (`.modeConfigurationApplied` is defined but currently unused)
- Prompts/language: `.promptDidChange`, `.languageDidChange`
- Navigation/window: `.navigateToDestination`, `.showMainWindowRequested`
- Misc: `.AppSettingsDidChange`, `.openFileForTranscription`, `.audioDeviceSwitchRequired`

The Shortcuts layer additionally defines `ShortcutStore.shortcutDidChange`.

### Build Commands

**Using Taskfile (recommended):**

```bash
task setup
task build              # debug
task build:local        # ad-hoc signed
task build:open         # build + launch
task build:universal    # universal binary
task release            # release
task install            # install to /Applications
task clean              # clean artifacts
task check              # health checks
task test               # all tests
task test:unit          # unit tests only
task test:ui            # UI tests only
task test:fork          # fork config tests
task run                # launch built app
task dev                # build + watch
task dev:xcode          # open in Xcode
```

**Using Make (alternative):**

```bash
make                    # check + build
make whisper            # build whisper.xcframework (~/.voiceink)
make build              # debug build
make local              # ad-hoc signed → ~/Downloads/VoiceInk.app
make run                # launch built app
make dev                # build + run
make check              # environment health check
make clean              # clean (removes ~/.voiceink)
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
- Does this maintain backward compatibility (including the one-shot migrations and legacy key reads)?
- Is the performance impact acceptable?
- Are external services properly gated by configuration?
- Will this work for all fork configurations (and for ad-hoc-signed local builds)?
- Can the behavior vary per mode — and if so, is it resolved through `ModeRuntimeResolver` rather than globals?

Focus on maintaining the existing patterns and architecture. The codebase is well-structured — follow the established conventions for consistency. The fork configuration system enables customization without code changes.
