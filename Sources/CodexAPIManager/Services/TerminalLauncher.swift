import AppKit
import Darwin
import Foundation

struct CodexDesktopLauncher {
    func launch(
        profile: ProviderProfile,
        paths: RuntimePaths,
        workingDirectory: String,
        apiKey _: String?
    ) throws -> Int32 {
        let appURL = try apiCodexAppURL()
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
        environment["NO_PROXY"] = "127.0.0.1,localhost,::1"
        environment["no_proxy"] = "127.0.0.1,localhost,::1"
        environment.removeValue(forKey: "CODEX_API_KEY")
        environment.removeValue(forKey: "OPENAI_API_KEY")
        // The child talks only to the loopback Plus router. Provider secrets
        // stay in this manager process and are injected per selected model.

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
        let pid = process.processIdentifier
        try "\(pid)\n".write(to: paths.desktopPIDFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.desktopPIDFile.path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }

        return pid
    }

    private func terminatePreviousInstance(paths: RuntimePaths) {
        guard let pid = runningProcessID(paths: paths) else { return }
        _ = kill(pid, SIGTERM)
        usleep(400_000)
    }

    func isRunning(paths: RuntimePaths) -> Bool {
        runningProcessID(paths: paths) != nil
    }

    @discardableResult
    func activateRunning(paths: RuntimePaths) -> Bool {
        guard let pid = runningProcessID(paths: paths),
              let application = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return application.activate(options: [.activateAllWindows])
    }

    private func runningProcessID(paths: RuntimePaths) -> Int32? {
        guard let pidText = try? String(contentsOf: paths.desktopPIDFile),
              let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0,
              kill(pid, 0) == 0 else { return nil }

        let output = Pipe()
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", "\(pid)", "-o", "args="]
        ps.standardOutput = output
        ps.standardError = FileHandle.nullDevice
        try? ps.run()
        let args = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        ps.waitUntilExit()
        guard args.contains(paths.desktopDataDirectory.path) else { return nil }
        return pid
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

    private func apiCodexAppURL() throws -> URL {
        guard let url = InstalledApplicationLocator.apiCodexApplicationURL() else {
            throw LaunchError.apiAppNotFound
        }
        return url
    }

    private func officialCodexAppURL() throws -> URL {
        guard let url = InstalledApplicationLocator.officialCodexApplicationURL() else {
            throw LaunchError.officialAppNotFound
        }
        return url
    }

    private func bundleExecutableName(at appURL: URL) throws -> String {
        guard let executable = Bundle(url: appURL)?.object(
            forInfoDictionaryKey: "CFBundleExecutable"
        ) as? String,
              !executable.isEmpty else {
            throw LaunchError.officialExecutableNotFound
        }
        return executable
    }
}

enum LaunchError: LocalizedError {
    case apiAppNotFound
    case officialAppNotFound
    case officialExecutableNotFound

    var errorDescription: String? {
        switch self {
        case .apiAppNotFound:
            "未找到 Codex API Plus 或官方 Codex 应用，请先安装其中一个。"
        case .officialAppNotFound: "未找到官方 Codex 应用。"
        case .officialExecutableNotFound: "官方 Codex 应用不完整，找不到可执行文件。"
        }
    }
}
