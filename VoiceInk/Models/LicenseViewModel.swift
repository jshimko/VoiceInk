import Foundation
import AppKit

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }
    
    @Published private(set) var licenseState: LicenseState = .trial(daysRemaining: 7)  // Default to trial
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published private(set) var activationsLimit: Int = 0
    
    private let trialPeriodDays = 7
    private let userDefaults = UserDefaults.standard
    private let config = AppConfig.shared
    private let polarService = PolarService()

    init() {
        loadLicenseState()
    }
    
    func startTrial() {
        // Only set trial start date if it hasn't been set before
        if userDefaults.trialStartDate == nil {
            userDefaults.trialStartDate = Date()
            licenseState = .trial(daysRemaining: trialPeriodDays)
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }
    }
    
    private func loadLicenseState() {
        // Check if license validation is enabled via configuration
        if config.enableLicenseValidation {
            // Original license validation logic
            if let licenseKey = userDefaults.licenseKey {
                self.licenseKey = licenseKey

                // Check if we have a stored activation ID
                if userDefaults.activationId != nil {
                    // Assume valid for now, actual validation happens asynchronously
                    licenseState = .licensed
                } else {
                    // Check trial period
                    if let trialStartDate = userDefaults.trialStartDate {
                        let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
                        let daysRemaining = trialPeriodDays - daysSinceStart

                        if daysRemaining > 0 {
                            licenseState = .trial(daysRemaining: daysRemaining)
                        } else {
                            licenseState = .trialExpired
                        }
                    } else {
                        licenseState = .trial(daysRemaining: trialPeriodDays)
                    }
                }
            } else {
                // No license key stored - check trial status
                if let trialStartDate = userDefaults.trialStartDate {
                    let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
                    let daysRemaining = trialPeriodDays - daysSinceStart

                    if daysRemaining > 0 {
                        licenseState = .trial(daysRemaining: daysRemaining)
                    } else {
                        licenseState = .trialExpired
                    }
                } else {
                    licenseState = .trial(daysRemaining: trialPeriodDays)
                }
            }
        } else {
            // License validation disabled - operate as fully licensed
            licenseState = .licensed

            // Load any previously entered key for display purposes
            if let licenseKey = userDefaults.licenseKey {
                self.licenseKey = licenseKey
            }
        }

        // Mark as launched (keep for compatibility)
        let hasLaunchedBefore = userDefaults.bool(forKey: "VoiceInkHasLaunchedBefore")
        if !hasLaunchedBefore {
            userDefaults.set(true, forKey: "VoiceInkHasLaunchedBefore")
        }
    }

    var canUseApp: Bool {
        if config.enableLicenseValidation {
            // Original validation - check license state
            switch licenseState {
            case .licensed:
                return true
            case .trial(let daysRemaining):
                return daysRemaining > 0
            case .trialExpired:
                return false
            }
        } else {
            // Validation disabled - always allow app usage
            return true
        }
    }

    func openPurchaseLink() {
        if let purchaseURL = config.purchaseURL,
           !purchaseURL.isEmpty,
           let url = URL(string: purchaseURL) {
            NSWorkspace.shared.open(url)
        } else {
            print("Purchase link not configured")
        }
    }

    func validateLicense() async {
        isValidating = true
        validationMessage = nil

        // Check if license validation is enabled
        if config.enableLicenseValidation {
            // Perform actual license validation
            guard !licenseKey.isEmpty else {
                validationMessage = "Please enter a license key"
                isValidating = false
                return
            }

            do {
                // First check if the license requires activation
                let (isValid, requiresActivation, activationsLimit) = try await polarService.checkLicenseRequiresActivation(licenseKey)

                if !isValid {
                    validationMessage = "Invalid license key"
                    licenseState = .trialExpired
                    isValidating = false
                    return
                }

                // Store the license key
                userDefaults.licenseKey = licenseKey

                if requiresActivation {
                    // License requires activation
                    if let storedActivationId = userDefaults.activationId {
                        // We have an existing activation ID, validate with it
                        let isValidWithActivation = try await polarService.validateLicenseKeyWithActivation(licenseKey, activationId: storedActivationId)

                        if isValidWithActivation {
                            licenseState = .licensed
                            validationMessage = "License validated successfully"
                            self.activationsLimit = activationsLimit ?? 0
                            userDefaults.activationsLimit = activationsLimit ?? 0
                        } else {
                            // Activation ID is no longer valid, need to activate again
                            let (newActivationId, limit) = try await polarService.activateLicenseKey(licenseKey)
                            userDefaults.activationId = newActivationId
                            userDefaults.activationsLimit = limit
                            self.activationsLimit = limit
                            licenseState = .licensed
                            validationMessage = "License activated successfully"
                        }
                    } else {
                        // No activation ID stored, need to activate
                        let (activationId, limit) = try await polarService.activateLicenseKey(licenseKey)
                        userDefaults.activationId = activationId
                        userDefaults.activationsLimit = limit
                        self.activationsLimit = limit
                        licenseState = .licensed
                        validationMessage = "License activated successfully"
                    }

                    userDefaults.set(true, forKey: "VoiceInkLicenseRequiresActivation")
                } else {
                    // License doesn't require activation
                    licenseState = .licensed
                    validationMessage = "License validated successfully"
                    userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
                }

                NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)

            } catch {
                validationMessage = error.localizedDescription
                licenseState = .trialExpired
            }
        } else {
            // License validation disabled - accept any key
            if !licenseKey.isEmpty {
                userDefaults.licenseKey = licenseKey
            }

            // Simulate validation delay for UI consistency
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second

            // Always mark as licensed when validation is disabled
            licenseState = .licensed
            validationMessage = "License accepted (validation disabled)"
            NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        }

        isValidating = false
    }
    
    func removeLicense() {
        // Remove both license key and trial data
        userDefaults.licenseKey = nil
        userDefaults.activationId = nil
        userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
        userDefaults.trialStartDate = nil
        userDefaults.set(false, forKey: "VoiceInkHasLaunchedBefore")  // Allow trial to restart
        
        userDefaults.activationsLimit = 0
        
        licenseState = .trial(daysRemaining: trialPeriodDays)  // Reset to trial state
        licenseKey = ""
        validationMessage = nil
        activationsLimit = 0
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        loadLicenseState()
    }
}


// Add UserDefaults extensions for storing activation ID
extension UserDefaults {
    var activationId: String? {
        get { string(forKey: "VoiceInkActivationId") }
        set { set(newValue, forKey: "VoiceInkActivationId") }
    }
    
    var activationsLimit: Int {
        get { integer(forKey: "VoiceInkActivationsLimit") }
        set { set(newValue, forKey: "VoiceInkActivationsLimit") }
    }
}
