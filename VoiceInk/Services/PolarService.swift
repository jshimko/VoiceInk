import Foundation
import IOKit
import os

/// Analytics and license validation service that communicates with Polar.sh API
/// This service is conditionally enabled based on the EnableAnalytics feature flag.
class PolarService {
    private let config = AppConfig.shared

    // Use configured values or fall back to defaults
    private var organizationId: String {
        config.analyticsOrganizationID ?? "Org"
    }

    private var apiToken: String {
        config.analyticsAPIToken ?? "Token"
    }

    private var baseURL: String {
        // Allow custom base URL if needed
        if let url = config.licenseValidationURL, !url.isEmpty {
            return url
        }
        return "https://api.polar.sh"
    }

    private lazy var logger = Logger(subsystem: config.loggerSubsystem, category: "PolarService")

    // Check if analytics is enabled
    private var isEnabled: Bool {
        config.enableAnalytics
    }

    // Create an authenticated URLRequest for the given endpoint
    private func createAuthenticatedRequest(endpoint: String, method: String = "POST") -> URLRequest? {
        // Return nil if analytics is disabled
        guard isEnabled else {
            logger.debug("PolarService: Analytics disabled via configuration")
            return nil
        }

        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    struct LicenseValidationResponse: Codable {
        let status: String
        let limit_activations: Int?
        let id: String?
        let activation: ActivationResponse?
    }

    struct ActivationResponse: Codable {
        let id: String
    }

    struct ActivationRequest: Codable {
        let key: String
        let organization_id: String
        let label: String
        let meta: [String: String]
    }

    struct ActivationResult: Codable {
        let id: String
        let license_key: LicenseKeyInfo
    }

    struct LicenseKeyInfo: Codable {
        let limit_activations: Int
        let status: String
    }

    // Generate a unique device identifier using shared logic
    private func getDeviceIdentifier() -> String {
        return Obfuscator.getDeviceIdentifier()
    }

    // Check if a license key requires activation
    func checkLicenseRequiresActivation(_ key: String) async throws -> (isValid: Bool, requiresActivation: Bool, activationsLimit: Int?) {
        guard var request = createAuthenticatedRequest(endpoint: "/v1/license-keys/validate") else {
            // Analytics disabled - always return valid license
            return (isValid: true, requiresActivation: false, activationsLimit: nil)
        }
        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.notice("🔑 License validation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                throw LicenseError.validationFailed(errorMsg)
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")

        let validationResponse = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        let isValid = validationResponse.status == "granted"

        // If limit_activations is nil or 0, the license doesn't require activation
        let requiresActivation = (validationResponse.limit_activations ?? 0) > 0

        return (isValid: isValid, requiresActivation: requiresActivation, activationsLimit: validationResponse.limit_activations)
    }

    // Activate a license key on this device
    func activateLicenseKey(_ key: String) async throws -> (activationId: String, activationsLimit: Int) {
        guard var request = createAuthenticatedRequest(endpoint: "/v1/license-keys/activate") else {
            // Analytics disabled - return dummy activation
            return (activationId: "dummy-activation-id", activationsLimit: 0)
        }
        let deviceId = getDeviceIdentifier()
        let hostname = Host.current().localizedName ?? "Unknown Mac"

        let activationRequest = ActivationRequest(
            key: key,
            organization_id: organizationId,
            label: hostname,
            meta: ["device_id": deviceId]
        )

        request.httpBody = try JSONEncoder().encode(activationRequest)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.notice("🔑 License activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")

                // Check for specific error messages
                if errorMsg.contains("activation limit") || errorMsg.contains("maximum activations") {
                    throw LicenseError.activationLimitReached(errorMsg)
                }
                if errorMsg.contains("License key does not require activation") {
                    throw LicenseError.activationNotRequired
                }
                throw LicenseError.activationFailed(errorMsg)
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")

        let activationResult = try JSONDecoder().decode(ActivationResult.self, from: data)

        return (activationId: activationResult.id, activationsLimit: activationResult.license_key.limit_activations)
    }

    // Validate a license key with an activation ID
    func validateLicenseKeyWithActivation(_ key: String, activationId: String) async throws -> Bool {
        guard var request = createAuthenticatedRequest(endpoint: "/v1/license-keys/validate") else {
            // Analytics disabled - always return valid
            return true
        }
        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId,
            "activation_id": activationId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.notice("🔑 License validation with activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                throw LicenseError.validationFailed(errorMsg)
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation with activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")

        let validationResponse = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)

        return validationResponse.status == "granted"
    }

    // MARK: - Analytics Methods

    func trackAppLaunch() {
        guard isEnabled else { return }
        // Implementation for tracking app launches
        logger.debug("Analytics: App launch tracked")
    }

    func trackFeatureUsage(_ feature: String) {
        guard isEnabled else { return }
        // Implementation for tracking feature usage
        logger.debug("Analytics: Feature usage tracked - \(feature)")
    }

    func trackError(_ error: String) {
        guard isEnabled else { return }
        // Implementation for tracking errors
        logger.debug("Analytics: Error tracked - \(error)")
    }
}

enum LicenseError: Error, LocalizedError {
    case activationFailed(String)
    case validationFailed(String)
    case activationLimitReached(String)
    case activationNotRequired

    var errorDescription: String? {
        switch self {
        case .activationFailed(let details):
            return "Failed to activate license: \(details)"
        case .validationFailed(let details):
            return "License validation failed: \(details)"
        case .activationLimitReached(let details):
            return "Activation limit reached: \(details)"
        case .activationNotRequired:
            return "This license does not require activation."
        }
    }
}