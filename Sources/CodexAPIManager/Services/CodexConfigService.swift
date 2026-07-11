import Foundation

struct RuntimePaths {
    let supportDirectory: URL
    let profilesFile: URL
    let codexHome: URL
    let activeProfileFile: URL
    let activeAuthModeFile: URL
    let workingDirectoryFile: URL
    let launcherFile: URL
    let desktopDataDirectory: URL
    let desktopLogFile: URL
    let modelCatalogFile: URL
    let authFile: URL
    let desktopPIDFile: URL
}

struct CodexConfigService {
    let paths: RuntimePaths

    static func defaultPaths(fileManager: FileManager = .default) throws -> RuntimePaths {
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let support = supportRoot.appendingPathComponent("Codex API Manager", isDirectory: true)
        let codexHome = support.appendingPathComponent("codex-home", isDirectory: true)
        return RuntimePaths(
            supportDirectory: support,
            profilesFile: support.appendingPathComponent("profiles.json"),
            codexHome: codexHome,
            activeProfileFile: support.appendingPathComponent("active-profile"),
            activeAuthModeFile: support.appendingPathComponent("active-auth-mode"),
            workingDirectoryFile: support.appendingPathComponent("working-directory"),
            launcherFile: support.appendingPathComponent("启动 Codex API.command"),
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
    }

    func writeConfiguration(for profile: ProviderProfile, workingDirectory: String, apiKey: String?) throws {
        try prepareDirectories()
        try writeModelCatalog(for: profile)
        try writeAuthFile(apiKey: apiKey, required: profile.authenticationMode.needsKey)
        let providerID = profile.providerID
        var lines = [
            "#:schema https://developers.openai.com/codex/config-schema.json",
            "model = \"\(TOMLEscaping.string(profile.model))\"",
            "model_provider = \"\(providerID)\"",
            "model_catalog_json = \"\(TOMLEscaping.string(paths.modelCatalogFile.path))\"",
            "plan_mode_reasoning_effort = \"xhigh\"",
            "model_reasoning_effort = \(profile.model == "gpt-5.6-sol" ? "\"max\"" : "\"high\"")",
            "disable_response_storage = true",
            "supports_websockets = false",
            "approval_policy = \"on-request\"",
            "sandbox_mode = \"workspace-write\"",
            "check_for_update_on_startup = false",
            "web_search = \"disabled\"",
            "",
            "[model_providers.\(providerID)]",
            "name = \"\(TOMLEscaping.string(profile.name))\"",
            "base_url = \"\(TOMLEscaping.string(profile.baseURL))\"",
            "wire_api = \"responses\"",
            "requires_openai_auth = \(profile.authenticationMode.needsKey ? "true" : "false")"
        ]

        switch profile.authenticationMode {
        case .bearer:
            lines.append("env_key = \"OPENAI_API_KEY\"")
        case .customHeader:
            let header = TOMLEscaping.string(profile.authenticationHeader)
            lines.append("env_http_headers = { \"\(header)\" = \"OPENAI_API_KEY\" }")
        case .none:
            break
        }

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

    private func writeAuthFile(apiKey: String?, required: Bool) throws {
        let object: [String: String] = required && apiKey?.isEmpty == false
            ? ["OPENAI_API_KEY": apiKey!]
            : [:]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: paths.authFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.authFile.path)
    }

    private func writeModelCatalog(for profile: ProviderProfile) throws {
        let candidates = [
            "/Applications/Codex Office.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let codexBinary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ConfigServiceError.codexCLINotFound
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBinary)
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

        let slugs: [String]
        if profile.baseURL.localizedCaseInsensitiveContains("cctq.ai") {
            // Keep all three CCTQ GPT-5.6 entries available to the desktop
            // model picker. The runtime uses this catalog before making the
            // request, so writing only the active entry breaks model switching.
            slugs = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        } else {
            slugs = [profile.model]
        }

        let catalogModels = slugs.map { slug -> [String: Any] in
            var model = baseline
            model["slug"] = slug
            model["display_name"] = slug
            model["description"] = "Custom Responses API model via \(profile.name)"
            model["visibility"] = "list"
            model["supported_in_api"] = true
            model["priority"] = 0
            model["availability_nux"] = NSNull()
            model["upgrade"] = NSNull()
            if slug == "gpt-5.6-sol",
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
        let keychainService = TOMLEscaping.shellSingleQuoted(KeychainService.service)

        let script = """
        #!/bin/zsh
        set -eu

        SUPPORT_DIR=\(support)
        export CODEX_HOME=\(codexHome)
        PROFILE_ID="$(/bin/cat "$SUPPORT_DIR/active-profile" | /usr/bin/tr -d '\\r\\n')"
        AUTH_MODE="$(/bin/cat "$SUPPORT_DIR/active-auth-mode" | /usr/bin/tr -d '\\r\\n')"
        WORKING_DIR="$(/bin/cat "$SUPPORT_DIR/working-directory" | /usr/bin/tr -d '\\r\\n')"

        if [[ "$AUTH_MODE" != "none" ]]; then
          if ! API_KEY="$(/usr/bin/security find-generic-password -s \(keychainService) -a "$PROFILE_ID" -w 2>/dev/null)"; then
            print -r -- "未找到此配置的 API Key。请回到 Codex API 管理器保存密钥。"
            print -n -- "按回车关闭窗口…"
            read -r
            exit 1
          fi
          export OPENAI_API_KEY="$API_KEY"
          unset API_KEY
        fi

        CODEX_BIN=""
        for candidate in /opt/homebrew/bin/codex /usr/local/bin/codex "/Applications/Codex Office.app/Contents/Resources/codex"; do
          if [[ -x "$candidate" ]]; then
            CODEX_BIN="$candidate"
            break
          fi
        done
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
