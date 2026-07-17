import AppKit
import Foundation
import SwiftUI

struct EmailSupport {
    static func generateSupportEmailBody() -> String {
        let config = AppConfig.shared
        let systemInfo = SystemInfoService.shared.getSystemInfoString()

        return """

            ------------------------
            ✨ **SCREEN RECORDING HIGHLY RECOMMENDED** ✨
            ▶️ Create a quick screen recording showing the issue!
            ▶️ It helps me understand and fix the problem much faster.

            📝 ISSUE DETAILS:
            - What steps did you take before the issue occurred?
            - What did you expect to happen?
            - What actually happened instead?


            ## 📋 COMMON ISSUES:
            \(config.docsURL.map { "Check our docs before sending an email: \($0)" } ?? "")
            ------------------------

            System Information:
            \(systemInfo)


            """
    }

    static func generateSupportEmailURL() -> URL? {
        let config = AppConfig.shared
        let subject = "\(config.appName) Support Request"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(config.supportEmail)?subject=\(encodedSubject)")
    }

    static func openSupportEmail() {
        let config = AppConfig.shared
        let subject = "\(config.appName) Support Request"
        let body = generateSupportEmailBody()

        if let sharingService = NSSharingService(named: .composeEmail) {
            sharingService.recipients = [config.supportEmail]
            sharingService.subject = subject
            sharingService.perform(withItems: [body])
            return
        }

        SystemInfoService.shared.copySystemInfoToClipboard()

        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
}
