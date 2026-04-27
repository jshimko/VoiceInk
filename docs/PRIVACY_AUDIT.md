# VoiceInk Privacy Audit

> **Scope:** privacy and external-communication audit of the `docs-and-scripts` branch of this fork.
> **Last verified:** 2026-04-27 against the current tree.
> **Reviewer:** fork maintainer.

## TL;DR

Under the `Fork.plist` shipped on this branch, the app makes **zero automatic network calls on launch** beyond loading local resources. All phone-home subsystems (auto-update, analytics, license validation, announcements) are present in the source tree but disabled at runtime via feature flags. Any cloud transcription or AI-enhancement traffic only happens when the user explicitly chooses a cloud provider and supplies credentials. Local Whisper, FluidAudio (Parakeet), Apple Speech, and Ollama paths remain fully offline.

The doc that follows describes how each subsystem is gated, what residual risks exist, and what to verify at runtime.

## Audit Summary

| Category               | Items                | Status                                                           |
| ---------------------- | -------------------- | ---------------------------------------------------------------- |
| **Auto-updates**       | Sparkle              | 🔒 Gated — `EnableAutoUpdates` (default `false`)                 |
| **Analytics**          | PolarService         | 🔒 Gated — `EnableAnalytics` (default `false`)                   |
| **License validation** | PolarService methods | 🔒 Gated — `EnableLicenseValidation` (default `false`)           |
| **Announcements**      | AnnouncementsService | 🔒 Gated — `EnableAnnouncements` (default `false`)               |
| **HTTP cache**         | `URLCache.shared`    | ✅ Disabled at launch (`VoiceInk.swift:42`)                      |
| **Crash reporting**    | —                    | ✅ Not present                                                   |
| **Hardcoded UI URLs**  | Discord/website/etc. | ✅ Configurable; auto-hide when `Fork.plist` value is empty/nil  |
| **Bundle identifiers** | Logger/storage paths | ✅ Derived from `AppConfig.shared` (current prefix `com.jshimko`) |
| **Ollama**             | Local LLM path       | ✅ Reads only `UserDefaults["ollamaBaseURL"]` (default localhost) |

"Gated" means the code is present in the binary but every call site is wrapped in a runtime check on `AppConfig.shared.<flag>`, which on this branch is `false`.

## Verified `Fork.plist` baseline (current branch)

The shipped `Fork.plist` on `docs-and-scripts` sets every phone-home flag to `false` and every external service URL to an empty string:

```xml
<key>EnableAutoUpdates</key>       <false/>
<key>EnableLicenseValidation</key> <false/>
<key>EnableAnnouncements</key>     <false/>
<key>EnableAnalytics</key>         <false/>
<key>SparkleUpdateURL</key>        <string></string>
<key>LicenseValidationURL</key>    <string></string>
<key>AnnouncementsURL</key>        <string></string>
<key>AnalyticsAPIToken</key>       <string></string>
<key>AnalyticsOrganizationID</key> <string></string>
<key>BundleIdentifierPrefix</key>  <string>com.jshimko</string>
<key>LoggerSubsystem</key>         <string>com.jshimko.voiceink</string>
```

`AppConfig.swift` declares all flag/URL properties as `let`, so values are immutable for the process lifetime once loaded.

## Per-Subsystem Findings

### 1. Auto-updates (Sparkle)

**Status:** 🔒 Gated.

**Why the code stays:** keeping Sparkle in-tree but inert lets a downstream operator opt back in by flipping `EnableAutoUpdates` and supplying their own `SparkleUpdateURL`, without forking the fork.

**How it's gated:**

- Compile-time: `#if canImport(Sparkle)` wraps every Sparkle reference inside `UpdaterViewModel` (`VoiceInk/VoiceInk.swift:394, 408, 416, 424`). A build that omits Sparkle compiles.
- Runtime: each of the four Sparkle entry points (`init`, `toggleAutoUpdates`, `checkForUpdates`, `silentlyCheckForUpdates`) additionally checks `config.enableAutoUpdates` and no-ops when `false`.
- Launch path: `silentlyCheckForUpdates()` is called at `VoiceInk/VoiceInk.swift:281` but the runtime gate inside the function makes it a no-op.

**Network behavior on this branch:** none. With `EnableAutoUpdates = false`, the Sparkle controller is never instantiated and no appcast is fetched.

### 2. Analytics (PolarService)

**Status:** 🔒 Gated.

**File:** `VoiceInk/Services/PolarService.swift`.

**How it's gated:**

- Every `URLRequest` is built by `createRequest(endpoint:method:)` (lines 30–41), which short-circuits to `nil` when `config.enableAnalytics == false`.
- Each public method (`checkLicenseRequiresActivation`, `activateLicenseKey`, `validateLicenseKeyWithActivation`, `trackAppLaunch`, `trackFeatureUsage`, `trackError`) returns dummy data or no-ops when `createRequest` returns `nil` / the flag is `false`.
- Launch site: `PolarService().trackAppLaunch()` is called at `VoiceInk/VoiceInk.swift:289`, wrapped in `if AppConfig.shared.enableAnalytics`.

**Hardcoded fallback URL:** `https://api.polar.sh` (`PolarService.swift:19`). Used only when `LicenseValidationURL` is empty AND analytics is enabled — neither is true on this branch. See *Known Concerns* below.

**Network behavior on this branch:** none.

### 3. License Validation

**Status:** 🔒 Gated; behaviorally treats every install as licensed.

**File:** `VoiceInk/Models/LicenseViewModel.swift`.

**How it's gated:**

- `loadLicenseState()` (`LicenseViewModel.swift:45`) early-returns with `licenseState = .licensed` when `config.enableLicenseValidation == false`.
- `canUseFeature()` returns `true` unconditionally when validation is disabled (`LicenseViewModel.swift:94`).
- `validateLicense()` (`LicenseViewModel.swift:120`) likewise short-circuits to `.licensed` and never reaches the PolarService methods.

**Network behavior on this branch:** none. Trial-expiry logic (`LicenseViewModel.swift:77–84`) is reachable only when validation is enabled.

> Earlier audit revisions claimed license validation called Gumroad. That's incorrect for this codebase — when the flag is on, validation flows through `PolarService` against the Polar.sh API.

### 4. Announcements

**Status:** 🔒 Gated.

**File:** `VoiceInk/Services/AnnouncementsService.swift`.

**How it's gated:**

- `start()` (lines 33–37) early-returns when `config.enableAnnouncements == false`.
- `fetchAndMaybeShow()` (line 63) double-checks the flag before issuing a request, so even if a timer somehow survived a config change, no fetch fires.
- Lifecycle sites: `AnnouncementsService.shared.start()` at `VoiceInk/VoiceInk.swift:284` and `.stop()` at `VoiceInk/VoiceInk.swift:311` are both wrapped in `if AppConfig.shared.enableAnnouncements`.

**Hardcoded fallback URL:** `https://beingpax.github.io/VoiceInk/announcements.json` (`AnnouncementsService.swift:20`). Used only when `AnnouncementsURL` is empty AND announcements is enabled — neither is true on this branch. See *Known Concerns* below.

**Network behavior on this branch:** none.

### 5. ModelPrewarmService

**Status:** ✅ Safe by design (no external traffic possible).

**File:** `VoiceInk/Services/ModelPrewarmService.swift`.

**Why it deserves a section:** this service runs automatically on app launch (3-second delay, line 47–53) and every time the Mac wakes from sleep (line 56–62), so it's worth confirming it cannot leak network traffic.

**Why it's safe:** `shouldPrewarm()` (lines 95–115) only returns `true` when the currently-selected provider is `.whisper` or `.fluidAudio`. Cloud providers fall through to the `default` branch, which logs and returns `false`. The actual transcription call uses the bundled `esc.wav` resource and a local model — no external endpoint is reachable from this code path.

**Network behavior on this branch:** none. (Model files themselves are downloaded only when the user explicitly clicks "Download" in the model card UI.)

### 6. HTTP Response Cache

**Status:** ✅ Hardened.

**Behavior:** `VoiceInk/VoiceInk.swift:42` zeroes `URLCache.shared` at app `init()`:

```swift
URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
```

This prevents `URLSession.shared` responses from being persisted into `Cache.db` under the app's container — even cloud transcription / AI traffic the user opts into stays out of disk caches.

### 7. Hardcoded URLs in UI

**Status:** ✅ Configurable; UI auto-hides when not configured.

`AppConfig.swift` exposes the seven user-facing URL slots (`websiteURL`, `docsURL`, `discordURL`, `purchaseURL`, `donationURL`, `changelogURL`, `licensePortalURL`) plus support email. Views render the corresponding link/button only when the value is non-empty (e.g. `LicenseManagementView` uses `config.url(from:)` and skips the section on `nil`). On this branch every URL string is empty in `Fork.plist`, so none of these links exist in the running UI.

### 8. Bundle Identifiers

**Status:** ✅ Configurable.

All bundle identifiers, logger subsystems, and Application Support paths are derived from `AppConfig.shared.bundleIdentifierPrefix` (currently `com.jshimko`). No hardcoded identifier from upstream remains in the running code path.

## Multi-layer Gating Pattern

Each phone-home subsystem is guarded twice:

1. **At the call site in `VoiceInk.swift`** — e.g. `if AppConfig.shared.enableAnalytics { PolarService().trackAppLaunch() }`.
2. **Inside the service itself** — e.g. `createRequest()` returning `nil`, `start()` early-returning, `loadLicenseState()` short-circuiting to `.licensed`.

Result: even if a future contributor accidentally removes one gate, the other layer still neutralizes the call. This is the design property the doc is asserting on your behalf.

## Ollama Isolation

Confirmed: when the user selects an Ollama-backed AI enhancement model, all traffic is directed at the user-configured endpoint and never falls through to a cloud provider.

- `OllamaService.swift:6, 11, 28` — `baseURL` is loaded from `UserDefaults["ollamaBaseURL"]`, defaulting to `http://localhost:11434`.
- `AIService.swift:46` — the AIService getter for the Ollama base URL also reads the same UserDefaults key with the same default.
- `AIService.swift:420` — the URL setter persists user-supplied values back to that key.
- `AIEnhancementService.swift:221–231` — when the active provider is Ollama, the enhancement path returns immediately after invoking `OllamaService` and does not fall through to any cloud provider.

If the user leaves Ollama unconfigured, requests go to `http://localhost:11434` (their loopback interface) — never to an Anthropic/Beingpax/Polar/etc. host.

## Network Communication Map

| Trigger                                | Endpoint                                       | Conditions                                                        |
| -------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| App launch                             | (none)                                         | All four phone-home flags are `false` on this branch              |
| User clicks "Download" on Whisper card | `huggingface.co/ggerganov/whisper.cpp`         | Required to obtain local model; user-initiated                    |
| User clicks "Download" on FluidAudio   | FluidAudio SDK download endpoint               | Required for Parakeet; user-initiated                             |
| User selects a cloud transcription    | Provider-chosen (Groq/Gemini/Deepgram/etc.)    | User chose provider AND supplied API key                          |
| User enables AI enhancement (cloud)    | Provider-chosen                                | User chose provider AND supplied API key                          |
| User enables AI enhancement (Ollama)   | `UserDefaults["ollamaBaseURL"]` (loopback dft) | User chose Ollama; never leaves the host unless they re-pointed it |
| User clicks Send Diagnostics           | `mailto:` (local mail handler)                 | Composes email; no auto-send                                      |

## Bundled Dependencies (Swift PM)

From `VoiceInk.xcodeproj/.../Package.resolved`:

| Package                | Source                                      | Pin                                  |
| ---------------------- | ------------------------------------------- | ------------------------------------ |
| AXSwift                | `tisfeng/AXSwift`                           | tag `0.3.6`                          |
| FluidAudio             | `FluidInference/FluidAudio`                 | branch `main` *(mutable)*            |
| KeyboardShortcuts      | `sindresorhus/KeyboardShortcuts`            | tag `2.4.0`                          |
| KeySender              | `jordanbaird/KeySender`                     | tag `0.0.5`                          |
| LaunchAtLogin-Modern   | `sindresorhus/LaunchAtLogin-Modern`         | branch `main` *(mutable)*            |
| LLMkit                 | `Beingpax/LLMkit`                           | branch `main` *(mutable, upstream)*  |
| mediaremote-adapter    | `Beingpax/mediaremote-adapter`              | branch `master` *(mutable, upstream)*|
| SelectedTextKit        | `tisfeng/SelectedTextKit`                   | tag `2.6.2`                          |
| Sparkle                | `sparkle-project/Sparkle`                   | tag `2.8.0`                          |
| swift-atomics          | `apple/swift-atomics`                       | tag `1.3.0`                          |
| Zip                    | `marmelroy/Zip`                             | tag `2.1.2`                          |

No analytics, telemetry, or crash-reporting SDKs are bundled.

Mutable-branch pins are tracked in *Known Concerns* below.

## Runtime Behavior on Launch (current `Fork.plist`)

Sequence of events in `VoiceInkApp.init()` and `.onAppear` and what each one does on the network:

1. `URLCache.shared` zeroed → no network.
2. `AppDefaults.registerDefaults()` → no network.
3. SwiftData container constructed → no network (LOCAL_BUILD removes CloudKit; other builds may sync the dictionary store via CloudKit if entitled).
4. DI chain (`AIService`, `AIEnhancementService`, model managers, `VoiceInkEngine`, etc.) constructed → no network.
5. `ModelPrewarmService` schedules a 3-second delayed warmup → no network unless a local Whisper/FluidAudio model is selected, in which case it loads model files from the on-disk cache.
6. `silentlyCheckForUpdates()` called → **no-op** because `enableAutoUpdates == false`.
7. `if enableAnnouncements` → skipped.
8. `if enableAnalytics` → skipped.

Net effect: no outbound TCP from the app process at launch. Confirmable with `nettop -p <pid>` or Little Snitch.

## Privacy Guarantees (current branch)

- ✅ **No automatic network calls on launch** under the shipped `Fork.plist`.
- ✅ **No telemetry or analytics** transmissions.
- ✅ **No license validation** roundtrips; every install is `.licensed`.
- ✅ **No update checks** issued; Sparkle is unreachable.
- ✅ **No crash reporting** code in the codebase.
- ✅ **No HTTP response disk caching** (`URLCache.shared` zeroed).
- ✅ **No unique device identifier transmitted.** The IOKit-based fingerprint in `Obfuscator.swift` is only built when the (gated) PolarService activation path runs, which it doesn't on this branch.

User-data handling:

| Data type        | Storage                                              | Egress                                                                      |
| ---------------- | ---------------------------------------------------- | --------------------------------------------------------------------------- |
| Audio recordings | `AppConfig.shared.applicationSupportPath`            | None unless user selects a cloud transcription provider                     |
| Transcriptions   | SwiftData `default.store`                            | None                                                                        |
| Vocabulary/replacements | SwiftData `dictionary.store`                  | Optional CloudKit sync (only on signed builds without `LOCAL_BUILD` flag)   |
| API keys         | Keychain (`KeychainService`, `APIKeyManager`)        | Sent only to the provider the user configured                               |
| Settings         | `UserDefaults`                                       | None                                                                        |

## Known Concerns / Hardening Backlog

These are real residual issues. None of them affect runtime privacy on the current branch (they're either unreachable or supply-chain in nature), but they would matter for any downstream operator who flips a flag — or for anyone who wants the audit to be tamper-evident.

1. **Hardcoded fallback URLs in gated services.** `PolarService.swift:19` falls back to `https://api.polar.sh` and `AnnouncementsService.swift:20` falls back to `https://beingpax.github.io/VoiceInk/announcements.json` when the corresponding `*URL` is empty. Both are unreachable while their feature flags are `false`, but a future flag flip without an explicit URL override would silently restore upstream phone-home. Consider replacing the fallback with `nil` and refusing to construct a request without an explicitly configured URL.

2. **Mutable Swift Package pins.** `Package.resolved` pins `LLMkit`, `FluidAudio`, `LaunchAtLogin-Modern`, and `mediaremote-adapter` to a *branch* rather than a tag. SwiftPM records the resolved revision SHA, so reproducible builds are still possible from the lockfile, but a `swift package update` (or any tooling that re-resolves) could pull in unaudited code from upstream. Two of those packages (`LLMkit`, `mediaremote-adapter`) are sourced from the upstream maintainer `Beingpax`. Consider pinning to specific tags or vendoring.

3. **Silent fallback when `Fork.plist` is missing.** `AppConfig.swift:60–63` logs a warning and continues with built-in defaults if `Fork.plist` isn't bundled. Built-in defaults are also privacy-preserving (`com.voiceink` prefix, all flags `false`), but the warning is easy to miss. Consider failing loudly during `init` instead, so a misconfigured build is impossible to ship.

4. **`PRIVACY_AUDIT.md` is not enforced.** Nothing in CI re-validates the claims here against the code. A future commit could re-introduce a phone-home path without breaking a test. Consider a script under `scripts/` that greps for direct calls to `PolarService`, `AnnouncementsService`, or `Sparkle` outside their gated call sites.

## Verification Methods

### 1. Network monitor

```bash
# Get the running PID
PID=$(pgrep -f "VoiceInk.app/Contents/MacOS/VoiceInk")
sudo nettop -p "$PID"
```

Expected: only loopback (`127.0.0.1:11434`) traffic when Ollama is in use; nothing on app launch.

### 2. Code grep

```bash
# All gated call sites should be wrapped in a flag check
grep -nE "(PolarService|AnnouncementsService|silentlyCheckForUpdates)\(" VoiceInk/

# Any direct https:// strings outside expected providers/docs
grep -rnE "https?://" --include="*.swift" VoiceInk/
```

### 3. Static config check

```bash
# Confirm no flag is enabled in the bundled Fork.plist
plutil -p Fork.plist | grep -E "Enable(AutoUpdates|Analytics|Announcements|LicenseValidation)"
# All four should print `=> 0`
```

### 4. Charles / Little Snitch

For a definitive runtime check, run the app behind Charles Proxy or with Little Snitch in deny-all mode. The app should remain fully functional with local providers and never prompt for outbound permissions until the user explicitly selects a cloud provider.

## Compliance

GDPR-compliant by default on this branch: no personal data collected, no transmission without user consent, all data stays on device unless the user enables and configures a cloud service.

Suggested public-facing privacy statement:

> "This application processes data locally on your device. The default configuration performs no automatic network calls. Audio is sent to a third-party transcription service only when you explicitly select a cloud provider and supply your own API key."

## Change Log

| Revision | Date       | Notes                                                                                       |
| -------- | ---------- | ------------------------------------------------------------------------------------------- |
| Fork 1.0 | 2025-10-?? | Initial fork; introduced `Fork.plist` and gating pattern.                                   |
| Fork 1.1 | 2026-04-27 | Audit doc rewritten to reflect actual ground truth: services are *gated*, not *removed*. Added `URLCache` zeroing, `ModelPrewarmService`, multi-layer gating, Ollama isolation, and known-concerns sections. Corrected upstream URLs (Polar.sh, beingpax.github.io) and license-validation backend (Polar, not Gumroad). |
