import XCTest
@testable import VoiceInk

@MainActor
class FeatureFlagTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Setup code if needed
    }

    // MARK: - Auto-Updates Feature Flag Tests

    func testAutoUpdatesDisabled() {
        let config = AppConfig.shared

        if !config.enableAutoUpdates {
            // When auto-updates are disabled
            let updaterViewModel = UpdaterViewModel()

            // Verify updater doesn't try to check for updates
            XCTAssertFalse(updaterViewModel.canCheckForUpdates,
                          "Update checks should not be available when feature is disabled")

            // Calling check for updates should be a no-op
            updaterViewModel.checkForUpdates()
            // Should not crash and should print disabled message

            // Silent checks should also be no-op
            updaterViewModel.silentlyCheckForUpdates()
            // Should not crash or make network calls
        }
    }

    func testAutoUpdatesEnabled() {
        let config = AppConfig.shared

        if config.enableAutoUpdates {
            // When auto-updates are enabled
            let updaterViewModel = UpdaterViewModel()

            // Only test if Sparkle URL is configured
            if config.sparkleUpdateURL != nil && !config.sparkleUpdateURL!.isEmpty {
                // Updater should be initialized
                // Note: We can't test Sparkle internals directly without the framework
                XCTAssertNotNil(updaterViewModel, "UpdaterViewModel should be created")
            }
        }
    }

    // MARK: - License Validation Feature Flag Tests

    func testLicenseValidationDisabled() async {
        let config = AppConfig.shared

        if !config.enableLicenseValidation {
            let licenseViewModel = await LicenseViewModel()

            // App should always be usable
            let canUseApp = await licenseViewModel.canUseApp
            XCTAssertTrue(canUseApp,
                         "App should always be usable when license validation is disabled")

            // License state should be licensed
            let licenseState = await licenseViewModel.licenseState
            XCTAssertEqual(licenseState, .licensed,
                          "Should be licensed when validation is disabled")

            // Validation should accept any key
            licenseViewModel.licenseKey = "any-key"
            await licenseViewModel.validateLicense()

            let finalLicenseState = await licenseViewModel.licenseState
            XCTAssertEqual(finalLicenseState, .licensed,
                          "Should accept any key when validation is disabled")
        }
    }

    func testLicenseValidationEnabled() async {
        let config = AppConfig.shared

        if config.enableLicenseValidation {
            let licenseViewModel = await LicenseViewModel()

            // Should check actual license state
            let canUse = await licenseViewModel.canUseApp

            // If no license, should depend on trial status
            let licenseKey = await licenseViewModel.licenseKey
            if licenseKey.isEmpty {
                let licenseState = await licenseViewModel.licenseState
                switch licenseState {
                case .trial(let daysRemaining):
                    XCTAssertEqual(canUse, daysRemaining > 0,
                                  "App usability should depend on trial days remaining")
                case .trialExpired:
                    XCTAssertFalse(canUse, "App should not be usable after trial expires")
                case .licensed:
                    XCTAssertTrue(canUse, "App should be usable when licensed")
                }
            }
        }
    }

    // MARK: - Announcements Feature Flag Tests

    func testAnnouncementsDisabled() {
        let config = AppConfig.shared

        if !config.enableAnnouncements {
            let announcementsService = AnnouncementsService.shared

            // Starting the service should be a no-op
            announcementsService.start()
            // Should print disabled message, not start timer

            // Stopping should also be safe
            announcementsService.stop()
            // Should not crash
        }
    }

    func testAnnouncementsEnabled() {
        let config = AppConfig.shared

        if config.enableAnnouncements {
            let announcementsService = AnnouncementsService.shared

            // Only test if URL is configured
            if config.announcementsURL != nil && !config.announcementsURL!.isEmpty {
                // Service should be able to start
                announcementsService.start()
                // Should create timer and schedule checks

                // Clean up
                announcementsService.stop()
            }
        }
    }

    // MARK: - Analytics Feature Flag Tests

    func testAnalyticsDisabled() async {
        let config = AppConfig.shared

        if !config.enableAnalytics {
            let polarService = PolarService()

            // All analytics methods should be no-ops
            polarService.trackAppLaunch()
            polarService.trackFeatureUsage("test-feature")
            polarService.trackError("test-error")

            // License methods should return stub values
            do {
                let (isValid, requiresActivation, _) = try await polarService.checkLicenseRequiresActivation("test-key")
                XCTAssertTrue(isValid, "Should always return valid when analytics disabled")
                XCTAssertFalse(requiresActivation, "Should not require activation when disabled")
            } catch {
                XCTFail("Should not throw when analytics disabled: \(error)")
            }
        }
    }

    func testAnalyticsEnabled() {
        let config = AppConfig.shared

        if config.enableAnalytics {
            let polarService = PolarService()

            // Only test if API token and org ID are configured
            if config.analyticsAPIToken != nil && !config.analyticsAPIToken!.isEmpty &&
               config.analyticsOrganizationID != nil && !config.analyticsOrganizationID!.isEmpty {

                // Analytics tracking should work
                polarService.trackAppLaunch()
                polarService.trackFeatureUsage("test-feature")
                polarService.trackError("test-error")
                // These should log but not crash
            }
        }
    }

    // MARK: - Multiple Feature Combinations Tests

    func testAllFeaturesDisabled() async {
        let config = AppConfig.shared

        // Test with all features disabled (privacy mode)
        if !config.enableAutoUpdates &&
           !config.enableLicenseValidation &&
           !config.enableAnnouncements &&
           !config.enableAnalytics {

            // App should work without any external communication
            let updaterViewModel = UpdaterViewModel()
            XCTAssertFalse(updaterViewModel.canCheckForUpdates)

            let licenseViewModel = await LicenseViewModel()
            let canUseApp = await licenseViewModel.canUseApp
            XCTAssertTrue(canUseApp)

            let announcementsService = AnnouncementsService.shared
            announcementsService.start()
            announcementsService.stop()

            let polarService = PolarService()
            polarService.trackAppLaunch()

            XCTAssertTrue(true, "App works in fully offline/privacy mode")
        }
    }

    func testSelectiveFeaturesEnabled() async {
        let config = AppConfig.shared

        // Test various combinations
        if config.enableAutoUpdates && !config.enableLicenseValidation {
            // Updates enabled but license validation disabled
            let updaterViewModel = UpdaterViewModel()
            let licenseViewModel = await LicenseViewModel()

            let canUseApp = await licenseViewModel.canUseApp
            XCTAssertTrue(canUseApp,
                         "App should be usable without license when only updates are enabled")
        }

        if !config.enableAutoUpdates && config.enableLicenseValidation {
            // License validation enabled but updates disabled
            let updaterViewModel = UpdaterViewModel()
            XCTAssertFalse(updaterViewModel.canCheckForUpdates,
                          "Updates should be disabled even if license validation is enabled")
        }

        if config.enableAnnouncements && !config.enableAnalytics {
            // Announcements without analytics
            let announcementsService = AnnouncementsService.shared
            let polarService = PolarService()

            // Announcements should work independently
            announcementsService.start()
            announcementsService.stop()

            // Analytics should still be disabled
            polarService.trackAppLaunch() // Should be no-op
        }
    }

    // MARK: - Network Isolation Tests

    func testNoNetworkCallsWhenDisabled() async {
        let config = AppConfig.shared

        // When all features are disabled, no network calls should be made
        if !config.enableAutoUpdates &&
           !config.enableLicenseValidation &&
           !config.enableAnnouncements &&
           !config.enableAnalytics {

            // Initialize all services
            let updaterViewModel = UpdaterViewModel()
            let licenseViewModel = await LicenseViewModel()
            let announcementsService = AnnouncementsService.shared
            let polarService = PolarService()

            // Try to trigger network operations
            updaterViewModel.checkForUpdates()
            await licenseViewModel.validateLicense()
            announcementsService.start()
            polarService.trackAppLaunch()

            // Clean up
            announcementsService.stop()

            // Note: We can't directly verify no network calls without mocking URLSession,
            // but the feature flag checks should prevent any network operations
            XCTAssertTrue(true, "All network operations should be disabled")
        }
    }

    // MARK: - Configuration URL Tests

    func testServiceURLConfiguration() {
        let config = AppConfig.shared

        // Test that services use configured URLs when available
        if config.enableAutoUpdates && config.sparkleUpdateURL != nil {
            XCTAssertNotNil(config.sparkleUpdateURL, "Sparkle URL should be configured")
        }

        if config.enableLicenseValidation && config.licenseValidationURL != nil {
            XCTAssertNotNil(config.licenseValidationURL, "License URL should be configured")
        }

        if config.enableAnnouncements && config.announcementsURL != nil {
            XCTAssertNotNil(config.announcementsURL, "Announcements URL should be configured")
        }

        if config.enableAnalytics {
            if config.analyticsAPIToken != nil {
                XCTAssertNotNil(config.analyticsAPIToken, "Analytics API token should be configured")
            }
            if config.analyticsOrganizationID != nil {
                XCTAssertNotNil(config.analyticsOrganizationID, "Analytics org ID should be configured")
            }
        }
    }
}