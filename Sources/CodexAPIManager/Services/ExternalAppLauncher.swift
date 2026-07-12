import AppKit

enum ExternalAppLauncher {
    static func openChatGPT() {
        let classicAppPath = "/Applications/ChatGPT Classic.app"
        if FileManager.default.fileExists(atPath: classicAppPath) {
            let url = URL(fileURLWithPath: classicAppPath, isDirectory: true)
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        if let url = URL(string: "https://chatgpt.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}
