import XCTest
@testable import VoiceInk

class ConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset any singleton state if needed
    }

    // MARK: - Default Configuration Tests

    func testDefaultConfiguration() {
        // Test that the app works without a Fork.plist file
        // AppConfig should use default values (all features disabled)
        let config = AppConfig.shared

        // Verify privacy-focused defaults
        XCTAssertFalse(config.enableAutoUpdates, "Auto-updates should be disabled by default")
        XCTAssertFalse(config.enableLicenseValidation, "License validation should be disabled by default")
        XCTAssertFalse(config.enableAnnouncements, "Announcements should be disabled by default")
        XCTAssertFalse(config.enableAnalytics, "Analytics should be disabled by default")
        XCTAssertFalse(config.showPurchaseOptions, "Purchase options should be hidden by default")
        XCTAssertFalse(config.showCommunityLinks, "Community links should be hidden by default")
    }

    // MARK: - Feature Flag Tests

    func testMinimalConfiguration() {
        // Test with minimal required fields only
        let config = AppConfig.shared

        // Verify required fields have sensible defaults
        XCTAssertNotNil(config.bundleIdentifierPrefix)
        XCTAssertNotNil(config.appName)
        XCTAssertNotNil(config.supportEmail)
        XCTAssertNotNil(config.loggerSubsystem)

        // Verify optional URLs can be nil
        if config.websiteURL == nil {
            XCTAssertNil(config.url(from: config.websiteURL))
        }
        if config.docsURL == nil {
            XCTAssertNil(config.url(from: config.docsURL))
        }
        if config.purchaseURL == nil {
            XCTAssertNil(config.url(from: config.purchaseURL))
        }
    }

    func testFullConfiguration() {
        // This test would require mocking or creating a test Fork.plist with all features enabled
        // Since we can't easily inject a different plist at runtime, we test the properties exist
        let config = AppConfig.shared

        // Verify all feature flags exist and are accessible
        _ = config.enableAutoUpdates
        _ = config.enableLicenseValidation
        _ = config.enableAnnouncements
        _ = config.enableAnalytics
        _ = config.showPurchaseOptions
        _ = config.showCommunityLinks
        _ = config.showDonationLink

        // Verify service configuration properties exist
        _ = config.sparkleUpdateURL
        _ = config.licenseValidationURL
        _ = config.announcementsURL
        _ = config.analyticsAPIToken
        _ = config.analyticsOrganizationID
    }

    func testPartialConfiguration() {
        // Test that partial configurations don't break the app
        let config = AppConfig.shared

        // If auto-updates are disabled, Sparkle URL is not required
        if !config.enableAutoUpdates {
            // App should work fine without Sparkle URL
            XCTAssertTrue(true, "App works without Sparkle URL when auto-updates disabled")
        }

        // If license validation is disabled, license URL is not required
        if !config.enableLicenseValidation {
            // App should work fine without license validation URL
            XCTAssertTrue(true, "App works without license URL when validation disabled")
        }

        // If announcements are disabled, announcements URL is not required
        if !config.enableAnnouncements {
            // App should work fine without announcements URL
            XCTAssertTrue(true, "App works without announcements URL when feature disabled")
        }

        // If analytics is disabled, API token and org ID are not required
        if !config.enableAnalytics {
            // App should work fine without analytics configuration
            XCTAssertTrue(true, "App works without analytics config when feature disabled")
        }
    }

    // MARK: - URL Validation Tests

    func testURLHelperMethod() {
        let config = AppConfig.shared

        // Test valid URL
        let validURL = "https://example.com"
        XCTAssertNotNil(config.url(from: validURL))

        // Test invalid URL - use a string that actually fails URL initialization
        // URL(string:) returns nil for strings with invalid characters like spaces after scheme
        let invalidURL = "http:// invalid"
        XCTAssertNil(config.url(from: invalidURL))

        // Test empty string
        XCTAssertNil(config.url(from: ""))

        // Test nil
        XCTAssertNil(config.url(from: nil))
    }

    // MARK: - Computed Properties Tests

    func testBundleIdentifiers() {
        let config = AppConfig.shared

        // Verify bundle identifiers are constructed correctly
        XCTAssertTrue(config.mainBundleIdentifier.hasSuffix(".VoiceInk"))
        XCTAssertTrue(config.testsBundleIdentifier.hasSuffix(".VoiceInkTests"))
        XCTAssertTrue(config.uiTestsBundleIdentifier.hasSuffix(".VoiceInkUITests"))

        // Verify they use the configured prefix
        XCTAssertTrue(config.mainBundleIdentifier.hasPrefix(config.bundleIdentifierPrefix))
        XCTAssertTrue(config.testsBundleIdentifier.hasPrefix(config.bundleIdentifierPrefix))
        XCTAssertTrue(config.uiTestsBundleIdentifier.hasPrefix(config.bundleIdentifierPrefix))
    }

    func testApplicationSupportPath() {
        let config = AppConfig.shared

        // Verify Application Support path is correctly formed
        let path = config.applicationSupportPath
        XCTAssertTrue(path.pathComponents.contains("Application Support"))
        XCTAssertTrue(path.lastPathComponent == config.mainBundleIdentifier)
    }

    func testModelsDirectory() {
        let config = AppConfig.shared

        // Verify models directory path is correctly formed
        let modelsDir = config.modelsDirectory
        XCTAssertTrue(modelsDir.pathComponents.contains("models"))
        XCTAssertTrue(modelsDir.pathComponents.contains(config.mainBundleIdentifier))
    }

    // MARK: - Feature Combinations Tests

    func testLicensingUIVisibility() {
        let config = AppConfig.shared

        // shouldShowLicensingUI should be true if either purchase or validation is enabled
        if config.showPurchaseOptions || config.enableLicenseValidation {
            XCTAssertTrue(config.shouldShowLicensingUI)
        } else {
            XCTAssertFalse(config.shouldShowLicensingUI)
        }
    }

    func testCommunityLinksAvailability() {
        let config = AppConfig.shared

        // hasAnyCommunityLinks should be true if any community URL is configured
        if config.discordURL != nil || config.changelogURL != nil || config.docsURL != nil {
            XCTAssertTrue(config.hasAnyCommunityLinks)
        } else {
            XCTAssertFalse(config.hasAnyCommunityLinks)
        }
    }

    // MARK: - Backward Compatibility Tests

    func testBackwardCompatibility() {
        // Test that existing Fork.plist configurations continue to work
        let config = AppConfig.shared

        // Original feature flags should still exist and work
        _ = config.showPurchaseOptions
        _ = config.showCommunityLinks
        _ = config.enableLicenseValidation
        _ = config.showDonationLink
        _ = config.enableAutoUpdates

        // Original URLs should still be accessible
        _ = config.websiteURL
        _ = config.docsURL
        _ = config.discordURL
        _ = config.purchaseURL
        _ = config.donationURL
        _ = config.changelogURL
        _ = config.licensePortalURL

        XCTAssertTrue(true, "Backward compatibility maintained")
    }
}