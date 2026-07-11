import AppKit
import Foundation

if CommandLine.arguments.contains("--self-test") {
    do {
        try SelfTest.run()
        print("CodexAPIManager self-test: PASS")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("CodexAPIManager self-test: FAIL: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    let application = NSApplication.shared
    let applicationDelegate = AppDelegate()
    application.delegate = applicationDelegate
    application.setActivationPolicy(.regular)
    application.run()
}
