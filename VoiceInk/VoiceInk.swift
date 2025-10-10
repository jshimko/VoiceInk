import SwiftUI
import SwiftData
#if canImport(Sparkle)
import Sparkle
#endif
import AppKit
import OSLog
import AppIntents
import FluidAudio

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    
    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    
    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared
    
    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared
    
    init() {
        // Configure FluidAudio logging subsystem
        AppLogger.defaultSubsystem = "\(AppConfig.shared.loggerSubsystem).parakeet"
        
        do {
            let schema = Schema([
                Transcription.self
            ])
            
            // Create app-specific Application Support directory URL
            let appSupportURL = AppConfig.shared.applicationSupportPath
            
            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            
            // Configure SwiftData to use the conventional location
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Print SwiftData storage location
            if let url = container.mainContext.container.configurations.first?.url {
                print("💾 SwiftData storage location: \(url.path)")
            }
            
        } catch {
            fatalError("Failed to create ModelContainer for Transcription: \(error.localizedDescription)")
        }
        
        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)
        
        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)
        
        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)
        
        let whisperState = WhisperState(modelContext: container.mainContext, enhancementService: enhancementService)
        _whisperState = StateObject(wrappedValue: whisperState)
        
        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)
        
        let menuBarManager = MenuBarManager(
            updaterViewModel: updaterViewModel,
            whisperState: whisperState,
            container: container,
            enhancementService: enhancementService,
            aiService: aiService,
            hotkeyManager: hotkeyManager
        )
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        
        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        activeWindowService.configureWhisperState(whisperState)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)
        
        // Ensure no lingering recording state from previous runs
        Task {
            await whisperState.resetOnLaunch()
        }
        
        AppShortcuts.updateAppShortcutParameters()
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(whisperState)
                    .environmentObject(hotkeyManager)
                    .environmentObject(updaterViewModel)
                    .environmentObject(menuBarManager)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .modelContainer(container)
                    .onAppear {
                        // Conditionally start announcements service
                        if AppConfig.shared.enableAnnouncements {
                            AnnouncementsService.shared.start()
                        }

                        // Conditionally track app launch for analytics
                        if AppConfig.shared.enableAnalytics {
                            PolarService().trackAppLaunch()
                        }

                        // Start the transcription auto-cleanup service (handles immediate and scheduled transcript deletion)
                        transcriptionAutoCleanupService.startMonitoring(modelContext: container.mainContext)

                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }

                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        // Conditionally stop announcements service
                        if AppConfig.shared.enableAnnouncements {
                            AnnouncementsService.shared.stop()
                        }

                        whisperState.unloadModel()

                        // Stop the transcription auto-cleanup service
                        transcriptionAutoCleanupService.stopMonitoring()

                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(hotkeyManager)
                    .environmentObject(whisperState)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .frame(minWidth: 880, minHeight: 780)
                    .background(WindowAccessor { window in
                        // Ensure this is called only once or is idempotent
                        if window.title != "VoiceInk Onboarding" { // Prevent re-configuration
                            WindowManager.shared.configureOnboardingPanel(window)
                        }
                    })
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }
        
        MenuBarExtra {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.menu)
        
        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

// UpdaterViewModel with conditional Sparkle support based on feature flag
class UpdaterViewModel: ObservableObject {
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = false
    @Published var canCheckForUpdates = false

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif

    private let config = AppConfig.shared

    init() {
        #if canImport(Sparkle)
        if config.enableAutoUpdates {
            // Initialize Sparkle when auto-updates are enabled
            // Note: The feedURL should be configured in Info.plist with SUFeedURL key
            // or passed during initialization
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

            // Enable automatic update checking
            updaterController?.updater.automaticallyChecksForUpdates = autoUpdateCheck
            updaterController?.updater.updateCheckInterval = 24 * 60 * 60

            updaterController?.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        } else {
            print("Auto-updates disabled via configuration")
        }
        #else
        print("Sparkle framework not available - auto-updates disabled")
        #endif
    }

    func toggleAutoUpdates(_ value: Bool) {
        #if canImport(Sparkle)
        if config.enableAutoUpdates {
            updaterController?.updater.automaticallyChecksForUpdates = value
        }
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        if config.enableAutoUpdates {
            // This is for manual checks - will show UI
            updaterController?.checkForUpdates(nil)
        } else {
            print("Auto-updates disabled via configuration")
        }
        #else
        print("Auto-updates disabled - Sparkle not available")
        #endif
    }

    func silentlyCheckForUpdates() {
        #if canImport(Sparkle)
        if config.enableAutoUpdates {
            // This checks for updates in the background without showing UI unless an update is found
            updaterController?.updater.checkForUpdatesInBackground()
        }
        #endif
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}



