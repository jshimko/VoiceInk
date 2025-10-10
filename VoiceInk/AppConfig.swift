import Foundation
import OSLog

/// Central configuration for fork customization
/// Reads from Fork.plist to allow easy customization without code changes
final class AppConfig {
    static let shared = AppConfig()

    private let logger = Logger(subsystem: "voiceink.config", category: "AppConfig")

    // MARK: - Identity Configuration
    let bundleIdentifierPrefix: String
    let appName: String
    let supportEmail: String
    let loggerSubsystem: String

    // MARK: - Optional URLs
    let websiteURL: String?
    let docsURL: String?
    let discordURL: String?
    let purchaseURL: String?
    let donationURL: String?
    let changelogURL: String?
    let licensePortalURL: String?

    // MARK: - Feature Flags
    let showPurchaseOptions: Bool
    let showCommunityLinks: Bool
    let enableLicenseValidation: Bool
    let showDonationLink: Bool
    let enableAutoUpdates: Bool
    let enableAnnouncements: Bool
    let enableAnalytics: Bool

    // MARK: - Service Configuration URLs
    let sparkleUpdateURL: String?
    let licenseValidationURL: String?
    let announcementsURL: String?
    let analyticsAPIToken: String?
    let analyticsOrganizationID: String?

    // MARK: - Computed Properties
    var mainBundleIdentifier: String {
        "\(bundleIdentifierPrefix).VoiceInk"
    }

    var testsBundleIdentifier: String {
        "\(bundleIdentifierPrefix).VoiceInkTests"
    }

    var uiTestsBundleIdentifier: String {
        "\(bundleIdentifierPrefix).VoiceInkUITests"
    }

    private init() {
        // Try to load Fork.plist from the main bundle
        let configURL = Bundle.main.url(forResource: "Fork", withExtension: "plist")
        let config = configURL.flatMap { try? NSDictionary(contentsOf: $0, error: ()) }

        if config == nil {
            logger.warning("Fork.plist not found, using default configuration")
            logger.info("To customize, copy Fork.plist.template to Fork.plist and add to Xcode project")
        }

        // Load identity configuration with defaults
        bundleIdentifierPrefix = config?["BundleIdentifierPrefix"] as? String ?? "com.voiceink"
        appName = config?["AppName"] as? String ?? "VoiceInk"
        supportEmail = config?["SupportEmail"] as? String ?? "support@voiceink.app"
        loggerSubsystem = config?["LoggerSubsystem"] as? String ?? "\(bundleIdentifierPrefix).voiceink"

        // Load optional URLs
        websiteURL = config?["WebsiteURL"] as? String
        docsURL = config?["DocsURL"] as? String
        discordURL = config?["DiscordURL"] as? String
        purchaseURL = config?["PurchaseURL"] as? String
        donationURL = config?["DonationURL"] as? String
        changelogURL = config?["ChangelogURL"] as? String
        licensePortalURL = config?["LicensePortalURL"] as? String

        // Load feature flags with sensible defaults
        showPurchaseOptions = config?["ShowPurchaseOptions"] as? Bool ?? false
        showCommunityLinks = config?["ShowCommunityLinks"] as? Bool ?? false
        enableLicenseValidation = config?["EnableLicenseValidation"] as? Bool ?? false
        showDonationLink = config?["ShowDonationLink"] as? Bool ?? false
        enableAutoUpdates = config?["EnableAutoUpdates"] as? Bool ?? false
        enableAnnouncements = config?["EnableAnnouncements"] as? Bool ?? false
        enableAnalytics = config?["EnableAnalytics"] as? Bool ?? false

        // Load service configuration URLs
        sparkleUpdateURL = config?["SparkleUpdateURL"] as? String
        licenseValidationURL = config?["LicenseValidationURL"] as? String
        announcementsURL = config?["AnnouncementsURL"] as? String
        analyticsAPIToken = config?["AnalyticsAPIToken"] as? String
        analyticsOrganizationID = config?["AnalyticsOrganizationID"] as? String

        logger.info("AppConfig loaded - Bundle: \(self.bundleIdentifierPrefix), Features: purchase=\(self.showPurchaseOptions), community=\(self.showCommunityLinks), updates=\(self.enableAutoUpdates), analytics=\(self.enableAnalytics)")
    }

    // MARK: - Helper Methods

    /// Returns URL if the string is valid, nil otherwise
    func url(from urlString: String?) -> URL? {
        guard let urlString = urlString,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    /// Check if any community features are enabled
    var hasAnyCommunityLinks: Bool {
        discordURL != nil || changelogURL != nil || docsURL != nil
    }

    /// Check if the app should show pro/licensing UI
    var shouldShowLicensingUI: Bool {
        showPurchaseOptions || enableLicenseValidation
    }
}

// MARK: - Storage Paths Extension
extension AppConfig {
    /// Returns the Application Support directory path for this fork
    var applicationSupportPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(mainBundleIdentifier, isDirectory: true)
    }

    /// Returns the models directory path for Whisper models
    var modelsDirectory: URL {
        applicationSupportPath.appendingPathComponent("models", isDirectory: true)
    }
}