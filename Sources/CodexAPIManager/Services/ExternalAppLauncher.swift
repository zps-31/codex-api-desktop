import AppKit

enum ExternalAppLauncher {
    @discardableResult
    static func openMeter() -> Bool {
        guard let url = InstalledApplicationLocator.meterApplicationURL() else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return true
    }

    static func openChatGPT() {
        if let url = InstalledApplicationLocator.chatGPTClassicApplicationURL() {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        if let url = URL(string: "https://chatgpt.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}
