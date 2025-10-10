# VoiceInk Fork Configuration API Reference

> **Complete reference for Fork.plist configuration and AppConfig API**

## Table of Contents

- [Fork.plist Configuration](#forkplist-configuration)
- [AppConfig API](#appconfig-api)
- [UI Component Integration](#ui-component-integration)
- [Code Examples](#code-examples)
- [Extension Points](#extension-points)

## Fork.plist Configuration

### File Format

Fork.plist is an Apple Property List (XML format) that must be valid XML and conform to the plist DTD.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Configuration keys here -->
</dict>
</plist>
```

### Configuration Keys

> **Note:** With the feature flag refactoring, all external communication features are now controlled by explicit feature flags. Default values are privacy-focused (all features disabled).

#### Required Keys

##### BundleIdentifierPrefix

- **Type:** `String`
- **Required:** Yes
- **Default:** `"com.voiceink"`
- **Example:** `"com.mycompany"`
- **Usage:** Base for all bundle identifiers
- **Constraints:** Must be valid reverse DNS format

```xml
<key>BundleIdentifierPrefix</key>
<string>com.mycompany</string>
```

##### SupportEmail

- **Type:** `String`
- **Required:** Yes
- **Default:** `"support@voiceink.app"`
- **Example:** `"help@mycompany.com"`
- **Usage:** Email for support requests
- **Constraints:** Must be valid email format

```xml
<key>SupportEmail</key>
<string>help@mycompany.com</string>
```

#### Optional Identity Keys

##### AppName

- **Type:** `String`
- **Required:** No
- **Default:** `"VoiceInk"`
- **Example:** `"MyTranscriber"`
- **Usage:** Display name in UI
- **Constraints:** None

```xml
<key>AppName</key>
<string>MyTranscriber</string>
```

##### LoggerSubsystem

- **Type:** `String`
- **Required:** No
- **Default:** `"{BundleIdentifierPrefix}.voiceink"`
- **Example:** `"com.mycompany.transcription"`
- **Usage:** Console.app log filtering
- **Constraints:** Should follow reverse DNS format

```xml
<key>LoggerSubsystem</key>
<string>com.mycompany.transcription</string>
```

#### Optional URL Keys

All URL keys support empty strings to disable features.

##### WebsiteURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://mycompany.com"`
- **Usage:** Main website link
- **UI Effect:** Shows/hides website button

```xml
<key>WebsiteURL</key>
<string>https://mycompany.com</string>
```

##### DocsURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://docs.mycompany.com"`
- **Usage:** Documentation link
- **UI Effect:** Shows/hides docs button

```xml
<key>DocsURL</key>
<string>https://docs.mycompany.com</string>
```

##### ChangelogURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://github.com/mycompany/app/releases"`
- **Usage:** Release notes/changelog
- **UI Effect:** Shows/hides changelog button

```xml
<key>ChangelogURL</key>
<string>https://github.com/mycompany/app/releases</string>
```

##### DiscordURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://discord.gg/mycommunity"`
- **Usage:** Community/Discord link
- **UI Effect:** Shows/hides community button

```xml
<key>DiscordURL</key>
<string>https://discord.gg/mycommunity</string>
```

##### PurchaseURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://mycompany.com/buy"`
- **Usage:** Purchase/upgrade page
- **UI Effect:** Shows/hides purchase flow

```xml
<key>PurchaseURL</key>
<string>https://mycompany.com/buy</string>
```

##### DonationURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://patreon.com/myproject"`
- **Usage:** Donation/tip jar link
- **UI Effect:** Shows/hides donation button

```xml
<key>DonationURL</key>
<string>https://patreon.com/myproject</string>
```

##### LicensePortalURL

- **Type:** `String` (URL)
- **Required:** No
- **Default:** `nil`
- **Example:** `"https://licenses.mycompany.com"`
- **Usage:** License management portal
- **UI Effect:** Shows/hides portal link

```xml
<key>LicensePortalURL</key>
<string>https://licenses.mycompany.com</string>
```

#### Feature Flag Keys

##### ShowPurchaseOptions

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Enable purchase/licensing UI
- **UI Effect:** Shows/hides entire purchase flow

```xml
<key>ShowPurchaseOptions</key>
<true/>
```

##### ShowCommunityLinks

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Show community features
- **UI Effect:** Shows/hides Discord, forums, etc.

```xml
<key>ShowCommunityLinks</key>
<true/>
```

##### ShowDonationLink

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Show tip jar/donation
- **UI Effect:** Shows/hides donation button

```xml
<key>ShowDonationLink</key>
<false/>
```

##### EnableLicenseValidation

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Enable license checks (always false in fork)
- **Note:** Kept for compatibility, no effect

```xml
<key>EnableLicenseValidation</key>
<false/>
```

##### EnableAutoUpdates

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Enable Sparkle framework auto-updates
- **Note:** Requires SparkleUpdateURL to be configured when enabled

```xml
<key>EnableAutoUpdates</key>
<false/>
```

##### EnableAnnouncements

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Enable in-app announcements service
- **Note:** Requires AnnouncementsURL to be configured when enabled

```xml
<key>EnableAnnouncements</key>
<false/>
```

##### EnableAnalytics

- **Type:** `Boolean`
- **Required:** No
- **Default:** `false`
- **Usage:** Enable analytics and telemetry service
- **Note:** Requires AnalyticsAPIToken and AnalyticsOrganizationID when enabled

```xml
<key>EnableAnalytics</key>
<false/>
```

#### Service Configuration Keys

##### SparkleUpdateURL

- **Type:** `String`
- **Required:** Only if EnableAutoUpdates is `true`
- **Default:** `nil`
- **Usage:** URL for Sparkle update feed (appcast.xml)
- **Example:** `"https://example.com/appcast.xml"`

```xml
<key>SparkleUpdateURL</key>
<string>https://example.com/appcast.xml</string>
```

##### LicenseValidationURL

- **Type:** `String`
- **Required:** Only if EnableLicenseValidation is `true`
- **Default:** `nil`
- **Usage:** API endpoint for license validation
- **Example:** `"https://api.polar.sh"`

```xml
<key>LicenseValidationURL</key>
<string>https://api.polar.sh</string>
```

##### AnnouncementsURL

- **Type:** `String`
- **Required:** Only if EnableAnnouncements is `true`
- **Default:** `nil`
- **Usage:** URL for fetching announcements JSON
- **Example:** `"https://example.com/announcements.json"`

```xml
<key>AnnouncementsURL</key>
<string>https://example.com/announcements.json</string>
```

##### AnalyticsAPIToken

- **Type:** `String`
- **Required:** Only if EnableAnalytics is `true`
- **Default:** `nil`
- **Usage:** API token for analytics service
- **Security:** Store securely, do not commit to public repos

```xml
<key>AnalyticsAPIToken</key>
<string>your-api-token-here</string>
```

##### AnalyticsOrganizationID

- **Type:** `String`
- **Required:** Only if EnableAnalytics is `true`
- **Default:** `nil`
- **Usage:** Organization identifier for analytics service

```xml
<key>AnalyticsOrganizationID</key>
<string>your-org-id-here</string>
```

### Complete Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required -->
    <key>BundleIdentifierPrefix</key>
    <string>com.acme</string>
    <key>SupportEmail</key>
    <string>support@acme.com</string>

    <!-- Optional Identity -->
    <key>AppName</key>
    <string>AcmeTranscribe</string>
    <key>LoggerSubsystem</key>
    <string>com.acme.transcribe</string>

    <!-- Optional URLs -->
    <key>WebsiteURL</key>
    <string>https://acme.com/transcribe</string>
    <key>DocsURL</key>
    <string>https://docs.acme.com</string>
    <key>ChangelogURL</key>
    <string>https://github.com/acme/transcribe/releases</string>
    <key>PurchaseURL</key>
    <string>https://acme.com/buy</string>

    <!-- Feature Flags -->
    <key>ShowPurchaseOptions</key>
    <true/>
    <key>ShowCommunityLinks</key>
    <false/>
    <key>EnableLicenseValidation</key>
    <false/>
    <key>ShowDonationLink</key>
    <false/>
    <key>EnableAutoUpdates</key>
    <false/>
    <key>EnableAnnouncements</key>
    <false/>
    <key>EnableAnalytics</key>
    <false/>

    <!-- Service Configuration (only needed if corresponding feature is enabled) -->
    <key>SparkleUpdateURL</key>
    <string></string>
    <key>LicenseValidationURL</key>
    <string></string>
    <key>AnnouncementsURL</key>
    <string></string>
    <key>AnalyticsAPIToken</key>
    <string></string>
    <key>AnalyticsOrganizationID</key>
    <string></string>
</dict>
</plist>
```

## AppConfig API

### Class Definition

```swift
final class AppConfig {
    static let shared = AppConfig()
    private init() { /* Singleton */ }
}
```

### Properties

#### Identity Properties

##### bundleIdentifierPrefix

```swift
let bundleIdentifierPrefix: String
```

- **Type:** `String`
- **Access:** Read-only
- **Description:** Organization's bundle ID prefix
- **Example:** `"com.mycompany"`

##### appName

```swift
let appName: String
```

- **Type:** `String`
- **Access:** Read-only
- **Description:** Application display name
- **Example:** `"VoiceInk"`

##### supportEmail

```swift
let supportEmail: String
```

- **Type:** `String`
- **Access:** Read-only
- **Description:** Support email address
- **Example:** `"support@mycompany.com"`

##### loggerSubsystem

```swift
let loggerSubsystem: String
```

- **Type:** `String`
- **Access:** Read-only
- **Description:** Logger subsystem identifier
- **Example:** `"com.mycompany.voiceink"`

#### URL Properties

All URL properties are optional strings.

##### websiteURL

```swift
let websiteURL: String?
```

- **Type:** `String?`
- **Access:** Read-only
- **Description:** Main website URL
- **Example:** `"https://mycompany.com"`

##### docsURL

```swift
let docsURL: String?
```

- **Type:** `String?`
- **Access:** Read-only
- **Description:** Documentation URL
- **Example:** `"https://docs.mycompany.com"`

##### Additional URL Properties

```swift
let discordURL: String?
let purchaseURL: String?
let donationURL: String?
let changelogURL: String?
let licensePortalURL: String?
```

#### Feature Flags

##### showPurchaseOptions

```swift
let showPurchaseOptions: Bool
```

- **Type:** `Bool`
- **Access:** Read-only
- **Description:** Whether to show purchase UI
- **Default:** `false`

##### showCommunityLinks

```swift
let showCommunityLinks: Bool
```

- **Type:** `Bool`
- **Access:** Read-only
- **Description:** Whether to show community links
- **Default:** `false`

##### showDonationLink

```swift
let showDonationLink: Bool
```

- **Type:** `Bool`
- **Access:** Read-only
- **Description:** Whether to show donation options
- **Default:** `false`

##### enableLicenseValidation

```swift
let enableLicenseValidation: Bool
```

- **Type:** `Bool`
- **Access:** Read-only
- **Description:** Whether to validate licenses
- **Default:** `false`

##### enableAutoUpdates

```swift
let enableAutoUpdates: Bool
```

- **Type:** `Bool`
- **Access:** Read-only
- **Description:** Whether to check for updates
- **Default:** `false`

### Computed Properties

##### mainBundleIdentifier

```swift
var mainBundleIdentifier: String { get }
```

- **Returns:** Complete bundle identifier
- **Example:** `"com.mycompany.VoiceInk"`
- **Formula:** `"{bundleIdentifierPrefix}.VoiceInk"`

##### testsBundleIdentifier

```swift
var testsBundleIdentifier: String { get }
```

- **Returns:** Tests bundle identifier
- **Example:** `"com.mycompany.VoiceInkTests"`
- **Formula:** `"{bundleIdentifierPrefix}.VoiceInkTests"`

##### uiTestsBundleIdentifier

```swift
var uiTestsBundleIdentifier: String { get }
```

- **Returns:** UI tests bundle identifier
- **Example:** `"com.mycompany.VoiceInkUITests"`
- **Formula:** `"{bundleIdentifierPrefix}.VoiceInkUITests"`

##### hasAnyCommunityLinks

```swift
var hasAnyCommunityLinks: Bool { get }
```

- **Returns:** Whether any community links configured
- **Logic:** `discordURL != nil || changelogURL != nil || docsURL != nil`

##### shouldShowLicensingUI

```swift
var shouldShowLicensingUI: Bool { get }
```

- **Returns:** Whether to show licensing features
- **Logic:** `showPurchaseOptions || enableLicenseValidation`

### Methods

##### url(from:)

```swift
func url(from urlString: String?) -> URL?
```

- **Parameters:**
  - `urlString`: Optional URL string
- **Returns:** Valid URL or nil
- **Description:** Safely converts string to URL
- **Example:**

```swift
if let url = config.url(from: config.websiteURL) {
    NSWorkspace.shared.open(url)
}
```

### Storage Extensions

##### applicationSupportPath

```swift
var applicationSupportPath: URL { get }
```

- **Returns:** Application Support directory URL
- **Example:** `~/Library/Application Support/com.mycompany.VoiceInk/`

##### modelsDirectory

```swift
var modelsDirectory: URL { get }
```

- **Returns:** Models storage directory
- **Example:** `~/Library/Application Support/com.mycompany.VoiceInk/models/`

## UI Component Integration

### Conditional Rendering Pattern

```swift
struct MyView: View {
    private let config = AppConfig.shared

    var body: some View {
        VStack {
            // Feature only renders if configured
            if let purchaseURL = config.purchaseURL,
               let url = config.url(from: purchaseURL) {
                Button("Purchase") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
```

### Feature Flag Pattern

```swift
struct SettingsView: View {
    private let config = AppConfig.shared

    var body: some View {
        VStack {
            if config.showPurchaseOptions {
                PurchaseSection()
            }

            if config.hasAnyCommunityLinks {
                CommunitySection()
            }
        }
    }
}
```

### Logger Integration

```swift
import os

class MyService {
    private let logger = Logger(
        subsystem: AppConfig.shared.loggerSubsystem,
        category: "MyService"
    )

    func doWork() {
        logger.info("Starting work...")
    }
}
```

### Storage Integration

```swift
class DataManager {
    private let storageURL = AppConfig.shared.applicationSupportPath

    func saveData(_ data: Data, filename: String) throws {
        let fileURL = storageURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
    }
}
```

## Code Examples

### Example 1: Complete View with Configuration

```swift
import SwiftUI

struct AboutView: View {
    private let config = AppConfig.shared
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    var body: some View {
        VStack(spacing: 20) {
            // App name from config
            Text(config.appName)
                .font(.largeTitle)
                .bold()

            Text("Version \(version)")
                .foregroundColor(.secondary)

            // Conditional buttons based on config
            HStack(spacing: 20) {
                if let websiteURL = config.websiteURL,
                   let url = config.url(from: websiteURL) {
                    Button("Website") {
                        NSWorkspace.shared.open(url)
                    }
                }

                if let docsURL = config.docsURL,
                   let url = config.url(from: docsURL) {
                    Button("Documentation") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Support") {
                    EmailSupport.openSupportEmail()
                }
            }

            // Feature sections
            if config.showPurchaseOptions {
                Divider()
                PurchaseSection()
            }

            if config.showDonationLink,
               let donationURL = config.donationURL,
               let url = config.url(from: donationURL) {
                Divider()
                Button("Support Development") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
```

### Example 2: Service with Configuration

```swift
import Foundation
import os

class UpdateService {
    private let config = AppConfig.shared
    private let logger: Logger

    init() {
        self.logger = Logger(
            subsystem: config.loggerSubsystem,
            category: "UpdateService"
        )
    }

    func checkForUpdates() {
        guard config.enableAutoUpdates else {
            logger.info("Auto-updates disabled")
            return
        }

        // Update logic here
        logger.info("Checking for updates...")
    }
}
```

### Example 3: Migration Helper

```swift
class MigrationHelper {
    static func migrateFromOriginal() {
        let oldBundle = "com.jshimko.VoiceInk"
        let newBundle = AppConfig.shared.mainBundleIdentifier

        // Migrate Application Support
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory,
                                         in: .userDomainMask)[0]

        let oldPath = appSupport.appendingPathComponent(oldBundle)
        let newPath = appSupport.appendingPathComponent(newBundle)

        if fileManager.fileExists(atPath: oldPath.path) &&
           !fileManager.fileExists(atPath: newPath.path) {
            try? fileManager.moveItem(at: oldPath, to: newPath)
        }

        // Migrate UserDefaults
        if let oldDefaults = UserDefaults(suiteName: oldBundle) {
            let newDefaults = UserDefaults.standard
            for (key, value) in oldDefaults.dictionaryRepresentation() {
                newDefaults.set(value, forKey: key)
            }
        }
    }
}
```

## Extension Points

### Adding New Configuration Keys

1. **Update Fork.plist.template:**

```xml
<key>MyNewFeature</key>
<string>default_value</string>
```

2. **Extend AppConfig:**

```swift
extension AppConfig {
    let myNewFeature: String

    // In init()
    myNewFeature = config?["MyNewFeature"] as? String ?? "default_value"
}
```

3. **Use in code:**

```swift
if config.myNewFeature == "enabled" {
    // Feature code
}
```

### Creating Configuration Profiles

```swift
enum ConfigProfile {
    case development
    case staging
    case production

    var plistName: String {
        switch self {
        case .development: return "Fork.dev"
        case .staging: return "Fork.staging"
        case .production: return "Fork"
        }
    }
}

class AppConfig {
    init(profile: ConfigProfile = .production) {
        let configURL = Bundle.main.url(
            forResource: profile.plistName,
            withExtension: "plist"
        )
        // Load configuration...
    }
}
```

### Dynamic Configuration Updates

```swift
extension AppConfig {
    func reload() {
        // Re-read Fork.plist
        // Update properties
        // Post notification
        NotificationCenter.default.post(
            name: .configurationDidChange,
            object: nil
        )
    }
}

extension Notification.Name {
    static let configurationDidChange = Notification.Name("configurationDidChange")
}
```

### Validation Helper

```swift
extension AppConfig {
    func validate() -> [String] {
        var errors: [String] = []

        // Validate bundle identifier
        if !bundleIdentifierPrefix.contains(".") {
            errors.append("Invalid bundle identifier prefix")
        }

        // Validate email
        if !supportEmail.contains("@") {
            errors.append("Invalid support email")
        }

        // Validate URLs
        for urlString in [websiteURL, docsURL, purchaseURL].compactMap({ $0 }) {
            if URL(string: urlString) == nil {
                errors.append("Invalid URL: \(urlString)")
            }
        }

        return errors
    }
}
```

## Best Practices

### Configuration Design

1. **Use optionals for features** - Allow disabling via nil
2. **Provide sensible defaults** - App works without config
3. **Validate early** - Check configuration at startup
4. **Document keys** - Clear descriptions in template
5. **Version config** - Track schema changes

### Code Integration

1. **Cache config reference** - `private let config = AppConfig.shared`
2. **Guard optional URLs** - Always validate before use
3. **Use computed properties** - For derived values
4. **Prefer feature flags** - Over checking URLs
5. **Log configuration** - Help debugging

### Testing

```swift
class AppConfigTests: XCTestCase {
    func testDefaultConfiguration() {
        // Test with no Fork.plist
        let config = AppConfig.shared
        XCTAssertEqual(config.bundleIdentifierPrefix, "com.voiceink")
    }

    func testURLValidation() {
        let url = AppConfig.shared.url(from: "invalid://url")
        XCTAssertNil(url)
    }

    func testBundleIdentifierGeneration() {
        let config = AppConfig.shared
        XCTAssertTrue(config.mainBundleIdentifier.hasSuffix(".VoiceInk"))
    }
}
```

---

_API Reference Version: 1.0_
_Last updated: October 2025_
_Compatible with: AppConfig v1.0+_
