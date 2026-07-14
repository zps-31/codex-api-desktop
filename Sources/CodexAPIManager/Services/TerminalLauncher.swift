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
            throw LaunchError.apiExecutableNotFound
        }

        try terminatePreviousInstance(paths: paths)
        try FileManager.default.createDirectory(
            at: paths.desktopDataDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let environment = Self.isolatedEnvironment(
            inherited: ProcessInfo.processInfo.environment,
            paths: paths
        )

        try Self.prepareLogFile(at: paths.desktopLogFile)
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

    static func isolatedEnvironment(
        inherited: [String: String],
        paths: RuntimePaths
    ) -> [String: String] {
        var environment = inherited
        let privateHome = paths.desktopHomeDirectory.path
        environment["HOME"] = privateHome
        environment["CFFIXED_USER_HOME"] = privateHome
        environment["XDG_CONFIG_HOME"] = paths.desktopHomeDirectory
            .appendingPathComponent(".config", isDirectory: true).path
        environment["XDG_CACHE_HOME"] = paths.desktopHomeDirectory
            .appendingPathComponent(".cache", isDirectory: true).path
        environment["XDG_DATA_HOME"] = paths.desktopHomeDirectory
            .appendingPathComponent(".local/share", isDirectory: true).path
        environment["CODEX_HOME"] = paths.codexHome.path
        environment["NO_PROXY"] = "127.0.0.1,localhost,::1"
        environment["no_proxy"] = "127.0.0.1,localhost,::1"
        for key in [
            "CODEX_API_KEY",
            "CODEX_CONFIG",
            "OPENAI_API_KEY",
            "OPENAI_API_BASE",
            "OPENAI_BASE_URL",
            "OPENAI_ORGANIZATION",
            "OPENAI_ORG_ID",
            "OPENAI_PROJECT_ID"
        ] {
            environment.removeValue(forKey: key)
        }
        // The child talks only to the loopback Plus router. Provider secrets
        // and every writable home/config surface remain outside official Codex.
        return environment
    }

    static func prepareLogFile(at url: URL) throws {
        let fileManager = FileManager.default
        let maximumBytes = 8 * 1_024 * 1_024
        let retainedBytes: UInt64 = 4 * 1_024 * 1_024
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maximumBytes {
            let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
            let input = try FileHandle(forReadingFrom: url)
            let end = try input.seekToEnd()
            try input.seek(toOffset: end > retainedBytes ? end - retainedBytes : 0)
            let tail = try input.readToEnd() ?? Data()
            try input.close()
            try tail.write(to: previous, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: previous.path
            )
            try Data().write(to: url, options: .atomic)
        } else if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func terminatePreviousInstance(paths: RuntimePaths) throws {
        guard let pid = runningProcessID(paths: paths) else { return }
        _ = kill(pid, SIGTERM)
        for _ in 0..<60 {
            if kill(pid, 0) != 0, errno == ESRCH {
                return
            }
            usleep(50_000)
        }
        throw LaunchError.previousInstanceDidNotExit
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
            throw LaunchError.apiExecutableNotFound
        }
        return executable
    }
}

enum LaunchError: LocalizedError {
    case apiAppNotFound
    case officialAppNotFound
    case apiExecutableNotFound
    case previousInstanceDidNotExit

    var errorDescription: String? {
        switch self {
        case .apiAppNotFound:
            "未找到独立的 Codex API Plus 应用。为保护官方账户配置，API 模式不会使用官方 Codex 作为回退。"
        case .officialAppNotFound: "未找到官方 Codex 应用。"
        case .apiExecutableNotFound: "Codex API Plus 应用不完整，找不到可执行文件。"
        case .previousInstanceDidNotExit:
            "旧的 API Codex 仍在退出。为避免数据目录冲突，请稍后再启动。"
        }
    }
}
