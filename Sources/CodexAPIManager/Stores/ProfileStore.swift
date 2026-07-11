import Foundation

final class ProfileStore {
    var profiles: [ProviderProfile] = []
    var selection: UUID?
    var activeProfileID: UUID?
    var workingDirectory: String
    var statusMessage = ""
    var showingError = false
    var errorMessage = ""

    private let keychain = KeychainService()
    private var configService: CodexConfigService
    private let launcher = CodexDesktopLauncher()

    init() {
        let fallbackDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Codex", isDirectory: true).path
        workingDirectory = fallbackDirectory

        do {
            let paths = try CodexConfigService.defaultPaths()
            configService = CodexConfigService(paths: paths)
            try configService.prepareDirectories()
            try load()
        } catch {
            let fallback = RuntimePaths(
                supportDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager"),
                profilesFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/profiles.json"),
                codexHome: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/codex-home"),
                activeProfileFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/active-profile"),
                activeAuthModeFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/active-auth-mode"),
                workingDirectoryFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/working-directory"),
                launcherFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/启动 Codex API.command"),
                desktopDataDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/desktop-data"),
                desktopLogFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/codex-desktop-api.log"),
                modelCatalogFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/model-catalog.json"),
                authFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/auth.json"),
                desktopPIDFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager/codex-desktop-api.pid")
            )
            configService = CodexConfigService(paths: fallback)
            profiles = [.template(.openAI), .template(.cctq), .template(.ollama)]
            selection = profiles.first?.id
            report(error)
        }
    }

    var selectedProfile: ProviderProfile? {
        guard let selection else { return nil }
        return profiles.first(where: { $0.id == selection })
    }

    var activeProfile: ProviderProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first(where: { $0.id == activeProfileID })
    }

    var runtimeDirectory: String { configService.paths.supportDirectory.path }

    func addProfile(_ preset: ProviderPreset) {
        let profile = ProviderProfile.template(preset)
        profiles.append(profile)
        selection = profile.id
        persistProfiles()
    }

    func duplicateSelected() {
        guard var profile = selectedProfile else { return }
        profile.id = UUID()
        profile.name += " 副本"
        profiles.append(profile)
        selection = profile.id
        persistProfiles()
    }

    func deleteSelected() {
        guard let selection,
              let index = profiles.firstIndex(where: { $0.id == selection }) else { return }
        let removed = profiles.remove(at: index)
        try? keychain.delete(account: removed.id.uuidString)
        if activeProfileID == removed.id { activeProfileID = nil }
        self.selection = profiles.indices.contains(index) ? profiles[index].id : profiles.last?.id
        persistProfiles()
        statusMessage = "已删除 \(removed.name)"
    }

    func saveProfiles() {
        do {
            for profile in profiles {
                try profile.validate(requireStoredKey: false, hasStoredKey: hasKey(for: profile))
            }
            try persistProfilesThrowing()
            if let active = activeProfile {
                let key = try apiKey(for: active)
                try configService.writeConfiguration(for: active, workingDirectory: workingDirectory, apiKey: key)
            }
            statusMessage = "配置已保存"
        } catch {
            report(error)
        }
    }

    func saveKey(_ key: String, for profile: ProviderProfile) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychain.save(trimmed, account: profile.id.uuidString)
            statusMessage = "API Key 已安全保存到 macOS 钥匙串"
        } catch {
            report(error)
        }
    }

    func clearKey(for profile: ProviderProfile) {
        do {
            try keychain.delete(account: profile.id.uuidString)
            statusMessage = "已从钥匙串移除 API Key"
        } catch {
            report(error)
        }
    }

    func hasKey(for profile: ProviderProfile) -> Bool {
        (try? apiKey(for: profile)) != nil
    }

    func activate(_ profile: ProviderProfile) {
        do {
            try profile.validate(requireStoredKey: true, hasStoredKey: hasKey(for: profile))
            guard FileManager.default.fileExists(atPath: workingDirectory) else {
                throw StoreError.invalidWorkingDirectory
            }
            activeProfileID = profile.id
            try persistProfilesThrowing()
            let key = try apiKey(for: profile)
            try configService.writeConfiguration(for: profile, workingDirectory: workingDirectory, apiKey: key)
            statusMessage = "已激活 \(profile.name) / \(profile.model)"
        } catch {
            report(error)
        }
    }

    func launchSelected() {
        guard let profile = selectedProfile else { return }
        activate(profile)
        guard activeProfileID == profile.id, !showingError else { return }
        do {
            let pid = try launcher.launch(
                profile: profile,
                paths: configService.paths,
                workingDirectory: workingDirectory,
                apiKey: try apiKey(for: profile)
            )
            statusMessage = "已启动独立 Codex 桌面 API 版（PID \(pid)）"
        } catch {
            report(error)
        }
    }

    func openOfficialCodex() {
        do {
            try launcher.openOfficialCodex()
            statusMessage = "已打开官方 Codex；它与 API 版使用不同配置目录"
        } catch {
            report(error)
        }
    }

    private func load() throws {
        if FileManager.default.fileExists(atPath: configService.paths.profilesFile.path) {
            let data = try Data(contentsOf: configService.paths.profilesFile)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            profiles = state.profiles
            activeProfileID = state.activeProfileID
            workingDirectory = state.workingDirectory
        } else {
            profiles = [.template(.openAI), .template(.ollama), .template(.generic)]
        }
        if profiles.isEmpty { profiles = [.template(.openAI)] }
        let migratedProfiles = profiles.map { profile -> ProviderProfile in
            guard profile.baseURL.localizedCaseInsensitiveContains("cctq.ai"),
                  !profile.model.hasPrefix("gpt-5.6-") else { return profile }
            var migrated = profile
            migrated.name = "cctq_codex"
            migrated.baseURL = "https://www.cctq.ai/v1"
            migrated.model = "gpt-5.5"
            migrated.preset = .cctq
            migrated.wireAPI = "responses"
            migrated.authenticationMode = .bearer
            migrated.authenticationHeader = "api-key"
            return migrated
        }
        if migratedProfiles != profiles {
            profiles = migratedProfiles
            try persistProfilesThrowing()
        }
        var seenProfileKeys: [String: UUID] = [:]
        var deduplicatedProfiles: [ProviderProfile] = []
        for profile in profiles {
            let key = "\(profile.baseURL)|\(profile.model)|\(profile.name)"
            if let keptID = seenProfileKeys[key] {
                if activeProfileID == profile.id { activeProfileID = keptID }
            } else {
                seenProfileKeys[key] = profile.id
                deduplicatedProfiles.append(profile)
            }
        }
        if deduplicatedProfiles.count != profiles.count {
            profiles = deduplicatedProfiles
            try persistProfilesThrowing()
        }
        let requiredCCTQ56: [ProviderPreset] = [.cctqSol, .cctqTerra, .cctqLuna]
        var addedCCTQ56 = false
        for preset in requiredCCTQ56 {
            let template = ProviderProfile.template(preset)
            if !profiles.contains(where: { $0.model == template.model && $0.baseURL == template.baseURL }) {
                profiles.append(template)
                addedCCTQ56 = true
            }
        }
        if addedCCTQ56 {
            try persistProfilesThrowing()
        }

        let activeModel = profiles.first(where: { $0.id == activeProfileID })?.model
        if activeModel?.hasPrefix("gpt-5.6-") != true,
           let sol = profiles.first(where: { $0.model == "gpt-5.6-sol" }) {
            activeProfileID = sol.id
            selection = sol.id
            try persistProfilesThrowing()
            let key = try apiKey(for: sol)
            try configService.writeConfiguration(for: sol, workingDirectory: workingDirectory, apiKey: key)
            statusMessage = "已自动切换到 CCTQ GPT-5.6 Sol"
        } else {
            selection = activeProfileID ?? profiles.first?.id
        }
    }

    private func persistProfiles() {
        do { try persistProfilesThrowing() } catch { report(error) }
    }

    private func apiKey(for profile: ProviderProfile) throws -> String? {
        if let key = try keychain.read(account: profile.id.uuidString) {
            return key
        }
        guard profile.baseURL.localizedCaseInsensitiveContains("cctq.ai") else { return nil }
        for candidate in profiles where candidate.id != profile.id && candidate.baseURL.localizedCaseInsensitiveContains("cctq.ai") {
            if let key = try keychain.read(account: candidate.id.uuidString) {
                return key
            }
        }
        return nil
    }

    private func persistProfilesThrowing() throws {
        try configService.prepareDirectories()
        let state = PersistedState(
            profiles: profiles,
            activeProfileID: activeProfileID,
            workingDirectory: workingDirectory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: configService.paths.profilesFile, options: .atomic)
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
        statusMessage = "操作未完成"
    }
}

private struct PersistedState: Codable {
    var profiles: [ProviderProfile]
    var activeProfileID: UUID?
    var workingDirectory: String
}

enum StoreError: LocalizedError {
    case invalidWorkingDirectory

    var errorDescription: String? {
        switch self {
        case .invalidWorkingDirectory: "工作目录不存在，请选择一个有效文件夹。"
        }
    }
}
