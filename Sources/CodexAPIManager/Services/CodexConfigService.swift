import Foundation

struct RuntimePaths {
    let supportDirectory: URL
    let profilesFile: URL
    let codexHome: URL
    let activeProfileFile: URL
    let activeAuthModeFile: URL
    let workingDirectoryFile: URL
    let launcherFile: URL
    let desktopHomeDirectory: URL
    let desktopDataDirectory: URL
    let desktopLogFile: URL
    let modelCatalogFile: URL
    let authFile: URL
    let desktopPIDFile: URL
}

struct CodexConfigurationSignature: Equatable {
    let modifiedAt: Date
    let size: Int
}

struct CodexConfigService {
    static let routerPort: UInt16 = 62139
    static let routerProviderID = "api_plus_router"

    static func modelAlias(for profile: ProviderProfile, in profiles: [ProviderProfile]) -> String {
        let duplicateCount = profiles.filter { $0.model == profile.model }.count
        guard duplicateCount > 1 else { return profile.model }
        let suffix = profile.id.uuidString.lowercased().prefix(8)
        return "\(profile.model)-api-plus-\(suffix)"
    }

    let paths: RuntimePaths

    static func defaultPaths(fileManager: FileManager = .default) throws -> RuntimePaths {
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let support = supportRoot.appendingPathComponent("Codex API Manager Plus", isDirectory: true)
        let codexHome = support.appendingPathComponent("codex-home", isDirectory: true)
        let desktopHome = support.appendingPathComponent("api-home", isDirectory: true)
        return RuntimePaths(
            supportDirectory: support,
            profilesFile: support.appendingPathComponent("profiles.json"),
            codexHome: codexHome,
            activeProfileFile: support.appendingPathComponent("active-profile"),
            activeAuthModeFile: support.appendingPathComponent("active-auth-mode"),
            workingDirectoryFile: support.appendingPathComponent("working-directory"),
            launcherFile: support.appendingPathComponent("启动 Codex API.command"),
            desktopHomeDirectory: desktopHome,
            desktopDataDirectory: support.appendingPathComponent("desktop-data", isDirectory: true),
            desktopLogFile: support.appendingPathComponent("codex-desktop-api.log"),
            modelCatalogFile: support.appendingPathComponent("model-catalog.json"),
            authFile: codexHome.appendingPathComponent("auth.json"),
            desktopPIDFile: support.appendingPathComponent("codex-desktop-api.pid")
        )
    }

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: paths.codexHome,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: paths.desktopDataDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for directory in [
            paths.desktopHomeDirectory,
            paths.desktopHomeDirectory.appendingPathComponent(".config", isDirectory: true),
            paths.desktopHomeDirectory.appendingPathComponent(".cache", isDirectory: true),
            paths.desktopHomeDirectory.appendingPathComponent(".local/share", isDirectory: true)
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    func configuredModel() -> String? {
        Self.configuredModel(at: paths.codexHome.appendingPathComponent("config.toml"))
    }

    static func configurationSignature(at file: URL) -> CodexConfigurationSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else {
            return nil
        }
        return CodexConfigurationSignature(
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            size: attributes[.size] as? Int ?? 0
        )
    }

    private static func configuredModel(at file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model = \"") else { continue }
            let value = trimmed.dropFirst("model = \"".count)
            guard let quote = value.firstIndex(of: "\"") else { return nil }
            return String(value[..<quote])
        }
        return nil
    }

    func writeConfiguration(
        for profile: ProviderProfile,
        profiles: [ProviderProfile],
        workingDirectory: String
    ) throws {
        try prepareDirectories()
        let orderedProfiles = [profile] + profiles.filter { $0.id != profile.id }
        try writeModelCatalog(for: orderedProfiles)
        try writeEmptyAuthFile()
        let modelReasoningEffort: String
        if profile.model == "gpt-5.6-sol", profile.workScenario == .deepDebug {
            modelReasoningEffort = "max"
        } else {
            modelReasoningEffort = profile.workScenario.modelReasoningEffort
        }
        let lines = [
            "#:schema https://developers.openai.com/codex/config-schema.json",
            "model = \"\(Self.modelAlias(for: profile, in: profiles))\"",
            "model_provider = \"\(Self.routerProviderID)\"",
            "model_catalog_json = \"\(TOMLEscaping.string(paths.modelCatalogFile.path))\"",
            "plan_mode_reasoning_effort = \"\(profile.workScenario.planReasoningEffort)\"",
            "model_reasoning_effort = \"\(modelReasoningEffort)\"",
            "disable_response_storage = true",
            "supports_websockets = false",
            "approval_policy = \"on-request\"",
            "sandbox_mode = \"\(profile.workScenario.sandboxMode)\"",
            "check_for_update_on_startup = false",
            "web_search = \"disabled\"",
            "",
            "[model_providers.\(Self.routerProviderID)]",
            "name = \"Codex API Plus 本机路由\"",
            "base_url = \"http://127.0.0.1:\(Self.routerPort)/v1\"",
            "wire_api = \"responses\"",
            "requires_openai_auth = false"
        ]

        let config = lines.joined(separator: "\n") + "\n"
        try config.write(
            to: paths.codexHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try (profile.id.uuidString + "\n").write(
            to: paths.activeProfileFile,
            atomically: true,
            encoding: .utf8
        )
        try (profile.authenticationMode.rawValue + "\n").write(
            to: paths.activeAuthModeFile,
            atomically: true,
            encoding: .utf8
        )
        try (workingDirectory + "\n").write(
            to: paths.workingDirectoryFile,
            atomically: true,
            encoding: .utf8
        )
        // The desktop build is launched directly by the manager. The legacy
        // .command file is left untouched so existing users do not lose it.
    }

    func writeEmptyAuthFile() throws {
        // Provider credentials remain in the manager and are injected by the
        // loopback router. Keep this compatibility file free of secrets.
        let data = try JSONSerialization.data(
            withJSONObject: [String: String](),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: paths.authFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.authFile.path)
    }

    private func writeModelCatalog(for profiles: [ProviderProfile]) throws {
        guard let codexBinary = InstalledApplicationLocator.codexCLIURL() else {
            throw ConfigServiceError.codexCLINotFound
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = codexBinary
        process.arguments = ["debug", "models", "--bundled"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]],
              let baseline = models.first(where: { $0["slug"] as? String == "gpt-5.5" })
                ?? models.first(where: { $0["slug"] as? String == "gpt-5.4" })
                ?? models.first else {
            throw ConfigServiceError.modelCatalogUnavailable
        }

        let catalogModels = profiles.map { profile -> [String: Any] in
            var model = baseline
            model["slug"] = Self.modelAlias(for: profile, in: profiles)
            model["display_name"] = profile.name
            model["description"] = "\(profile.model) · \(profile.baseURL)"
            model["visibility"] = "list"
            model["supported_in_api"] = true
            model["priority"] = 0
            model["availability_nux"] = NSNull()
            model["upgrade"] = NSNull()
            if profile.model == "gpt-5.6-sol",
               var levels = model["supported_reasoning_levels"] as? [[String: Any]],
               !levels.contains(where: { $0["effort"] as? String == "max" }) {
                levels.append(["effort": "max", "description": "Maximum reasoning depth for GPT-5.6 Sol"])
                model["supported_reasoning_levels"] = levels
                model["default_reasoning_level"] = "high"
            }
            return model
        }

        let catalog = ["models": catalogModels]
        let catalogData = try JSONSerialization.data(
            withJSONObject: catalog,
            options: [.prettyPrinted, .sortedKeys]
        )
        try catalogData.write(to: paths.modelCatalogFile, options: .atomic)
    }

    private func writeLauncher() throws {
        let support = TOMLEscaping.shellSingleQuoted(paths.supportDirectory.path)
        let codexHome = TOMLEscaping.shellSingleQuoted(paths.codexHome.path)
        let resolvedCodex = InstalledApplicationLocator.codexCLIURL()
            .map { TOMLEscaping.shellSingleQuoted($0.path) } ?? "''"

        let script = """
        #!/bin/zsh
        set -eu

        SUPPORT_DIR=\(support)
        export CODEX_HOME=\(codexHome)
        export NO_PROXY='127.0.0.1,localhost,::1'
        export no_proxy="$NO_PROXY"
        PROFILE_ID="$(/bin/cat "$SUPPORT_DIR/active-profile" | /usr/bin/tr -d '\\r\\n')"
        WORKING_DIR="$(/bin/cat "$SUPPORT_DIR/working-directory" | /usr/bin/tr -d '\\r\\n')"

        CODEX_BIN=\(resolvedCodex)
        if [[ -z "$CODEX_BIN" ]]; then
          CODEX_BIN="$(/bin/zsh -lic 'command -v codex' | /usr/bin/tail -n 1)"
        fi
        if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
          print -r -- "找不到 Codex CLI。请先安装或更新官方 Codex CLI。"
          print -n -- "按回车关闭窗口…"
          read -r
          exit 1
        fi

        cd "$WORKING_DIR"
        exec "$CODEX_BIN" --strict-config
        """

        try script.write(to: paths.launcherFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.launcherFile.path
        )
    }
}

enum ConfigServiceError: LocalizedError {
    case codexCLINotFound
    case modelCatalogUnavailable

    var errorDescription: String? {
        switch self {
        case .codexCLINotFound:
            return "找不到 Codex CLI，无法生成桌面版模型目录。"
        case .modelCatalogUnavailable:
            return "无法读取 Codex 内置模型目录，请更新或重新安装 Codex。"
        }
    }
}
