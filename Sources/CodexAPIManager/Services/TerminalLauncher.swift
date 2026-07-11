import AppKit
import Darwin
import Foundation

struct CodexDesktopLauncher {
    private let keychain = KeychainService()

    func launch(
        profile: ProviderProfile,
        paths: RuntimePaths,
        workingDirectory: String,
        apiKey: String?
    ) throws -> Int32 {
        let appURL = try officialCodexAppURL()
        let executableName = try bundleExecutableName(at: appURL)
        let executableURL = appURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LaunchError.officialExecutableNotFound
        }

        terminatePreviousInstance(paths: paths)
        try FileManager.default.createDirectory(
            at: paths.desktopDataDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = paths.codexHome.path
        environment.removeValue(forKey: "CODEX_API_KEY")
        environment.removeValue(forKey: "OPENAI_API_KEY")
        if profile.authenticationMode.needsKey {
            guard let apiKey else {
                throw ProfileValidationError.missingKey
            }
            environment["OPENAI_API_KEY"] = apiKey
        }

        if !FileManager.default.fileExists(atPath: paths.desktopLogFile.path) {
            FileManager.default.createFile(atPath: paths.desktopLogFile.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: paths.desktopLogFile)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--user-data-dir=\(paths.desktopDataDirectory.path)"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.environment = environment
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        try "\(process.processIdentifier)\n".write(to: paths.desktopPIDFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.desktopPIDFile.path)

        return process.processIdentifier
    }

    private func terminatePreviousInstance(paths: RuntimePaths) {
        guard let pidText = try? String(contentsOf: paths.desktopPIDFile),
              let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return }

        let output = Pipe()
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", "\(pid)", "-o", "args="]
        ps.standardOutput = output
        ps.standardError = FileHandle.nullDevice
        try? ps.run()
        let args = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        ps.waitUntilExit()
        guard args.contains(paths.desktopDataDirectory.path) else { return }
        _ = kill(pid, SIGTERM)
        usleep(400_000)
    }

    func openOfficialCodex() throws {
        let appURL = try officialCodexAppURL()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("Unable to open official Codex: %@", error.localizedDescription)
            }
        }
    }

    private func officialCodexAppURL() throws -> URL {
        let candidates = [
            "/Applications/Codex Office.app",
            "/Applications/Codex.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw LaunchError.officialAppNotFound
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func bundleExecutableName(at appURL: URL) throws -> String {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any],
              let executable = dictionary["CFBundleExecutable"] as? String,
              !executable.isEmpty else {
            throw LaunchError.officialExecutableNotFound
        }
        return executable
    }
}

enum LaunchError: LocalizedError {
    case officialAppNotFound
    case officialExecutableNotFound

    var errorDescription: String? {
        switch self {
        case .officialAppNotFound: "未找到官方 Codex 应用。"
        case .officialExecutableNotFound: "官方 Codex 应用不完整，找不到可执行文件。"
        }
    }
}
