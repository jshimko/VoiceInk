import Foundation
import SwiftUI
import AppKit

struct EmailSupport {
    static func generateSupportEmailURL() -> URL? {
        let config = AppConfig.shared
        let subject = "\(config.appName) Support Request"
        let systemInfo = SystemInfoService.shared.getSystemInfoString()

        let body = """

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

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return URL(string: "mailto:\(config.supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)")
    }
    
    static func openSupportEmail() {
        if let emailURL = generateSupportEmailURL() {
            NSWorkspace.shared.open(emailURL)
        }
    }
    
    
} 