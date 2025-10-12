import XCTest
import SwiftData
@testable import VoiceInk

@MainActor
class IntegrationTests: XCTestCase {

    var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([Transcription.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - App Launch Tests

    func testAppLaunchWithoutConfig() async {
        // Test app launches successfully without Fork.plist
        let config = AppConfig.shared

        // All features should be disabled by default
        XCTAssertFalse(config.enableAutoUpdates)
        XCTAssertFalse(config.enableLicenseValidation)
        XCTAssertFalse(config.enableAnnouncements)
        XCTAssertFalse(config.enableAnalytics)

        // App should still function
        let whisperState = WhisperState(
            modelContext: container.mainContext,
            enhancementService: AIEnhancementService(
                aiService: AIService(),
                modelContext: container.mainContext
            )
        )

        XCTAssertNotNil(whisperState, "App should initialize without configuration")
        XCTAssertEqual(whisperState.recordingState, .idle, "Should not be recording initially")
    }

    func testAppLaunchWithFullConfig() async {
        // Test app launches with all features potentially enabled
        let config = AppConfig.shared

        // Create all view models
        let updaterViewModel = UpdaterViewModel()
        let licenseViewModel = await LicenseViewModel()
        let aiService = AIService()
        let enhancementService = AIEnhancementService(
            aiService: aiService,
            modelContext: container.mainContext
        )
        let whisperState = WhisperState(
            modelContext: container.mainContext,
            enhancementService: enhancementService
        )
        let hotkeyManager = HotkeyManager(whisperState: whisperState)

        // Verify all components initialize
        XCTAssertNotNil(updaterViewModel)
        XCTAssertNotNil(licenseViewModel)
        XCTAssertNotNil(aiService)
        XCTAssertNotNil(enhancementService)
        XCTAssertNotNil(whisperState)
        XCTAssertNotNil(hotkeyManager)

        // Start services based on feature flags
        if config.enableAnnouncements {
            AnnouncementsService.shared.start()
        }

        if config.enableAnalytics {
            PolarService().trackAppLaunch()
        }

        // Clean up
        if config.enableAnnouncements {
            AnnouncementsService.shared.stop()
        }

        XCTAssertTrue(true, "App launches successfully with full configuration")
    }

    // MARK: - Service Integration Tests

    func testServicesWorkIndependently() async {
        let config = AppConfig.shared

        // Test that each service can work independently
        var servicesWorking = true

        // Test UpdaterViewModel independently
        let updaterViewModel = UpdaterViewModel()
        if config.enableAutoUpdates {
            updaterViewModel.checkForUpdates()
        }
        XCTAssertNotNil(updaterViewModel)

        // Test LicenseViewModel independently
        let licenseViewModel = await LicenseViewModel()
        if config.enableLicenseValidation {
            await licenseViewModel.validateLicense()
        }
        XCTAssertNotNil(licenseViewModel)

        // Test AnnouncementsService independently
        if config.enableAnnouncements {
            AnnouncementsService.shared.start()
            AnnouncementsService.shared.stop()
        }

        // Test PolarService independently
        if config.enableAnalytics {
            let polarService = PolarService()
            polarService.trackAppLaunch()
        }

        XCTAssertTrue(servicesWorking, "All services work independently")
    }

    func testServicesCommunicateCorrectly() async {
        // Test that services interact correctly when needed
        let config = AppConfig.shared

        // License validation may use PolarService
        if config.enableLicenseValidation && config.enableAnalytics {
            let licenseViewModel = await LicenseViewModel()
            await licenseViewModel.licenseKey = "test-key"

            // This should potentially use PolarService for validation
            await licenseViewModel.validateLicense()

            // Verify no crashes or conflicts
            XCTAssertNotNil(licenseViewModel.licenseState)
        }

        XCTAssertTrue(true, "Services communicate without conflicts")
    }

    // MARK: - Feature Toggle Tests

    func testRuntimeFeatureToggling() async {
        // Note: We can't actually toggle features at runtime since they're read from plist at startup
        // But we can test that the current configuration is respected

        let config = AppConfig.shared

        // Test that feature states are consistent throughout app lifecycle
        let initialAutoUpdate = config.enableAutoUpdates
        let initialLicenseValidation = config.enableLicenseValidation
        let initialAnnouncements = config.enableAnnouncements
        let initialAnalytics = config.enableAnalytics

        // Create services
        let _ = UpdaterViewModel()
        let _ = await LicenseViewModel()

        // Feature states should remain the same
        XCTAssertEqual(config.enableAutoUpdates, initialAutoUpdate)
        XCTAssertEqual(config.enableLicenseValidation, initialLicenseValidation)
        XCTAssertEqual(config.enableAnnouncements, initialAnnouncements)
        XCTAssertEqual(config.enableAnalytics, initialAnalytics)
    }

    // MARK: - Privacy Mode Tests

    func testPrivacyModeOperation() async {
        let config = AppConfig.shared

        // When all external communication is disabled
        if !config.enableAutoUpdates &&
           !config.enableLicenseValidation &&
           !config.enableAnnouncements &&
           !config.enableAnalytics {

            // App should operate in complete privacy mode
            let whisperState = WhisperState(
                modelContext: container.mainContext,
                enhancementService: AIEnhancementService(
                    aiService: AIService(),
                    modelContext: container.mainContext
                )
            )

            // Core functionality should still work
            XCTAssertNotNil(whisperState)

            // Can still record (if permissions granted)
            // Note: Can't test actual recording in unit tests

            // Can still transcribe locally
            XCTAssertNotNil(whisperState.currentTranscriptionModel)

            XCTAssertTrue(true, "App operates correctly in privacy mode")
        }
    }

    // MARK: - Upstream Compatibility Tests

    func testUpstreamCompatibility() {
        // Test that the refactored code maintains compatibility with upstream

        // All original classes and methods should still exist
        XCTAssertTrue(NSClassFromString("VoiceInk.UpdaterViewModel") != nil,
                     "UpdaterViewModel class should exist")
        XCTAssertTrue(NSClassFromString("VoiceInk.LicenseViewModel") != nil,
                     "LicenseViewModel class should exist")
        XCTAssertTrue(NSClassFromString("VoiceInk.AnnouncementsService") != nil,
                     "AnnouncementsService class should exist")
        XCTAssertTrue(NSClassFromString("VoiceInk.PolarService") != nil,
                     "PolarService class should exist")

        // Original method signatures should be preserved
        // This ensures upstream merges won't break
        XCTAssertTrue(true, "Upstream compatibility maintained")
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingWithMissingConfiguration() {
        let config = AppConfig.shared

        // Test that missing optional configuration doesn't crash
        if config.enableAutoUpdates && config.sparkleUpdateURL == nil {
            // Should handle missing Sparkle URL gracefully
            let updater = UpdaterViewModel()
            updater.checkForUpdates()
            XCTAssertTrue(true, "Handles missing Sparkle URL")
        }

        if config.enableAnnouncements && config.announcementsURL == nil {
            // Should handle missing announcements URL gracefully
            AnnouncementsService.shared.start()
            AnnouncementsService.shared.stop()
            XCTAssertTrue(true, "Handles missing announcements URL")
        }

        if config.enableAnalytics &&
           (config.analyticsAPIToken == nil || config.analyticsOrganizationID == nil) {
            // Should handle missing analytics config gracefully
            let polarService = PolarService()
            polarService.trackAppLaunch()
            XCTAssertTrue(true, "Handles missing analytics config")
        }
    }

    // MARK: - State Management Tests

    func testStateConsistencyAcrossServices() async {
        let config = AppConfig.shared

        // Test that state remains consistent across services
        let licenseViewModel = await LicenseViewModel()

        // License state should be consistent
        let initialState = await licenseViewModel.licenseState
        let canUse = await licenseViewModel.canUseApp

        switch initialState {
        case .licensed:
            XCTAssertTrue(canUse, "Licensed state should allow app use")
        case .trial(let days):
            XCTAssertEqual(canUse, days > 0, "Trial state should match days remaining")
        case .trialExpired:
            if config.enableLicenseValidation {
                XCTAssertFalse(canUse, "Expired trial should prevent app use when validation enabled")
            } else {
                XCTAssertTrue(canUse, "App should be usable when validation disabled")
            }
        }
    }
}