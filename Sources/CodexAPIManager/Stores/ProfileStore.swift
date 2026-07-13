import Darwin
import Foundation

final class ProfileStore {
    var profiles: [ProviderProfile] = []
    var selection: UUID?
    var activeProfileID: UUID?
    var workingDirectory: String
    var statusMessage = ""
    var showingError = false
    var errorMessage = ""
    var healthCheckReport: HealthCheckReport?
    var healthCheckProfileID: UUID?
    var launchHistory: [TaskBridgeRecord] = []

    private let keychain = KeychainService()
    private var configService: CodexConfigService
    private let launcher = CodexDesktopLauncher()
    private let proxy = APIProxyServer()
    private var runtimeMonitorTimer: DispatchSourceTimer?
    private var configurationWatcher: DispatchSourceFileSystemObject?
    private var lastCodexConfiguration: CodexConfigurationSignature?

    init() {
        let fallbackDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Codex", isDirectory: true).path
        workingDirectory = fallbackDirectory

        do {
            let paths = try CodexConfigService.defaultPaths()
            configService = CodexConfigService(paths: paths)
            try configService.prepareDirectories()
            try load()
            reconcileActiveProfileFromCodex()
            try synchronizeRuntime()
            lastCodexConfiguration = currentCodexConfiguration()
            launchHistory = TaskBridge.reconcileHistory()
        } catch {
            let fallback = RuntimePaths(
                supportDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus"),
                profilesFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/profiles.json"),
                codexHome: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/codex-home"),
                activeProfileFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/active-profile"),
                activeAuthModeFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/active-auth-mode"),
                workingDirectoryFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/working-directory"),
                launcherFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/启动 Codex API.command"),
                desktopHomeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/api-home"),
                desktopDataDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/desktop-data"),
                desktopLogFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/codex-desktop-api.log"),
                modelCatalogFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/model-catalog.json"),
                authFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/auth.json"),
                desktopPIDFile: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Codex API Manager Plus/codex-desktop-api.pid")
            )
            configService = CodexConfigService(paths: fallback)
            profiles = [.template(.openAI), .template(.cctq), .template(.ollama)]
            selection = profiles.first?.id
            report(error)
        }
        do {
            try proxy.ensureReady()
        } catch {
            report(error)
        }
        startRuntimeMonitoring()
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
    var sessionsDirectory: URL { configService.paths.codexHome.appendingPathComponent("sessions", isDirectory: true) }
    var availableProfiles: [ProviderProfile] { usableProfiles }
    var routerIsReady: Bool { proxy.isReady }
    var codexIsRunning: Bool { launcher.isRunning(paths: configService.paths) }
    var runtimeStatusText: String {
        let router = routerIsReady ? "路由正常" : "路由异常"
        let codex = codexIsRunning ? "API Codex 运行中" : "API Codex 未运行"
        return "\(router) · \(usableProfiles.count) 个模型 · \(codex)"
    }

    func addProfile(_ preset: ProviderPreset) {
        var profile = ProviderProfile.template(preset)
        profile.workspacePath = workingDirectory
        profiles.append(profile)
        selection = profile.id
        persistProfiles()
        try? synchronizeRuntime()
    }

    func selectProfile(_ profileID: UUID?) {
        selection = profileID
        if let profile = selectedProfile,
           let path = profile.workspacePath,
           !path.isEmpty {
            workingDirectory = path
        }
    }

    func duplicateSelected() {
        guard let selectedProfile else { return }
        let profile = selectedProfile.duplicated(existingNames: Set(profiles.map(\.name)))
        profiles.append(profile)
        selection = profile.id
        persistProfiles()
        try? synchronizeRuntime()
        statusMessage = "已复制为 \(profile.name) · API Key 未复制，请单独保存"
    }

    func deleteSelected() {
        guard let selection,
              let index = profiles.firstIndex(where: { $0.id == selection }) else { return }
        let removed = profiles.remove(at: index)
        try? keychain.delete(account: removed.id.uuidString)
        if activeProfileID == removed.id { activeProfileID = nil }
        self.selection = profiles.indices.contains(index) ? profiles[index].id : profiles.last?.id
        let codexWasRunning = launcher.isRunning(paths: configService.paths)
        do {
            try synchronizeRuntime()
            try persistProfilesThrowing()
            if codexWasRunning { try relaunchActiveCodex() }
        } catch { report(error) }
        statusMessage = "已删除 \(removed.name)"
    }

    func saveProfiles() {
        do {
            let codexWasRunning = launcher.isRunning(paths: configService.paths)
            for profile in profiles {
                try profile.validate(requireStoredKey: false, hasStoredKey: hasKey(for: profile))
            }
            try synchronizeRuntime()
            try persistProfilesThrowing()
            if codexWasRunning { try relaunchActiveCodex() }
            statusMessage = "配置已保存 · 已同步 \(usableProfiles.count) 个可用模型"
        } catch {
            report(error)
        }
    }

    func saveKey(_ key: String, for profile: ProviderProfile) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let codexWasRunning = launcher.isRunning(paths: configService.paths)
            try keychain.save(trimmed, account: profile.id.uuidString)
            try synchronizeRuntime(preferredProfile: profile)
            try persistProfilesThrowing()
            if codexWasRunning { try relaunchActiveCodex() }
            statusMessage = "API Key 已保存 · \(profile.name) 已加入 Codex 模型"
        } catch {
            report(error)
        }
    }

    func clearKey(for profile: ProviderProfile) {
        do {
            let codexWasRunning = launcher.isRunning(paths: configService.paths)
            try keychain.delete(account: profile.id.uuidString)
            try synchronizeRuntime()
            try persistProfilesThrowing()
            if codexWasRunning { try relaunchActiveCodex() }
            statusMessage = "已移除 API Key · \(profile.name) 已从 Codex 模型移除"
        } catch {
            report(error)
        }
    }

    func hasKey(for profile: ProviderProfile) -> Bool {
        guard profile.authenticationMode.needsKey else { return false }
        return keychain.contains(account: profile.id.uuidString)
    }

    func isAvailable(_ profile: ProviderProfile) -> Bool {
        Self.isAvailable(profile, hasStoredKey: hasKey(for: profile))
    }

    static func isAvailable(
        _ profile: ProviderProfile,
        hasStoredKey: Bool
    ) -> Bool {
        !profile.authenticationMode.needsKey || hasStoredKey
    }

    func activate(_ profile: ProviderProfile) {
        do {
            try profile.validate(requireStoredKey: true, hasStoredKey: hasKey(for: profile))
            guard FileManager.default.fileExists(atPath: workingDirectory) else {
                throw StoreError.invalidWorkingDirectory
            }
            _ = try apiKey(for: profile)
            try configService.writeConfiguration(
                for: profile,
                profiles: usableProfiles,
                workingDirectory: workingDirectory
            )
            let previousActiveProfileID = activeProfileID
            activeProfileID = profile.id
            do {
                try persistProfilesThrowing()
            } catch {
                activeProfileID = previousActiveProfileID
                throw error
            }
            showingError = false
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
            try proxy.ensureReady()
            try synchronizeRuntime(preferredProfile: profile)
            let pid = try launcher.launch(
                profile: profile,
                paths: configService.paths,
                workingDirectory: workingDirectory,
                apiKey: try apiKey(for: profile)
            )
            let task = try TaskBridge.writeStartedTask(
                profile: profile,
                workingDirectory: workingDirectory,
                processID: pid
            )
            launchHistory = TaskBridge.reconcileHistory()
            statusMessage = "已启动独立 Codex 桌面 API 版（PID \(pid)）· 已记录任务 \(task.projectName)"
        } catch {
            report(error)
        }
    }

    func focusAPICodex() {
        if launcher.activateRunning(paths: configService.paths) {
            statusMessage = "已切换到 API Plus 的 Codex 窗口"
        } else {
            statusMessage = "API Codex 尚未运行，请先检查并启动"
        }
    }

    func runHealthCheck(
        for profile: ProviderProfile,
        completion: @escaping () -> Void
    ) {
        let key: String?
        do {
            key = try apiKey(for: profile)
        } catch {
            healthCheckReport = HealthCheckReport(
                items: [
                    HealthCheckItem(
                        title: "凭据",
                        state: .failed,
                        detail: error.localizedDescription
                    )
                ],
                checkedAt: Date()
            )
            healthCheckProfileID = profile.id
            statusMessage = healthCheckReport?.summary ?? "启动前检查未完成"
            completion()
            return
        }

        Task {
            let report = await HealthCheckService.check(
                profile: profile,
                workingDirectory: workingDirectory,
                apiKey: key
            )
            await MainActor.run {
                healthCheckReport = report
                healthCheckProfileID = profile.id
                statusMessage = report.summary
                completion()
            }
        }
    }

    func healthCheckAndLaunch(completion: @escaping () -> Void) {
        guard let profile = selectedProfile else { return }
        statusMessage = "正在执行启动前检查…"
        runHealthCheck(for: profile) { [weak self] in
            guard let self else { return }
            if self.healthCheckReport?.items.contains(where: { $0.state == .failed }) == true {
                self.statusMessage = "启动已暂停：请先处理未通过的检查项"
            } else {
                self.launchSelected()
            }
            completion()
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
            let size = try configService.paths.profilesFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: configService.paths.profilesFile, options: .mappedIfSafe)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            profiles = Array(state.profiles.prefix(500))
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
        selection = activeProfileID ?? profiles.first?.id
        if let path = selectedProfile?.workspacePath, !path.isEmpty {
            workingDirectory = path
        }
    }

    private func persistProfiles() {
        do { try persistProfilesThrowing() } catch { report(error) }
    }

    private func apiKey(for profile: ProviderProfile) throws -> String? {
        guard profile.authenticationMode.needsKey else { return nil }
        return try keychain.read(account: profile.id.uuidString)
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

    private var usableProfiles: [ProviderProfile] {
        profiles.filter(isAvailable)
    }

    private func synchronizeRuntime(preferredProfile: ProviderProfile? = nil) throws {
        let available = usableProfiles
        let routes = available.map { profile in
            APIProxyRoute(
                alias: CodexConfigService.modelAlias(for: profile, in: available),
                profileName: profile.name,
                baseURL: profile.baseURL,
                model: profile.model,
                authenticationMode: profile.authenticationMode,
                authenticationHeader: profile.authenticationHeader,
                apiKey: try? apiKey(for: profile)
            )
        }
        proxy.update(routes: routes)
        guard let chosen = preferredProfile.flatMap({ preferred in
            available.first(where: { $0.id == preferred.id })
        }) ?? activeProfile.flatMap({ active in
            available.first(where: { $0.id == active.id })
        }) ?? available.first else { return }
        activeProfileID = chosen.id
        try configService.writeConfiguration(
            for: chosen,
            profiles: available,
            workingDirectory: chosen.workspacePath ?? workingDirectory
        )
        lastCodexConfiguration = currentCodexConfiguration()
    }

    private func reconcileActiveProfileFromCodex() {
        let available = usableProfiles
        guard let configured = configService.configuredModel(),
              let matched = available.first(where: {
                  CodexConfigService.modelAlias(for: $0, in: available) == configured
              }),
              matched.id != activeProfileID else { return }
        activeProfileID = matched.id
        try? persistProfilesThrowing()
        try? TaskBridge.updateActiveTask(profile: matched)
        launchHistory = TaskBridge.reconcileHistory()
        statusMessage = "Codex 已切换到 \(matched.name) / \(matched.model)"
    }

    private func startRuntimeMonitoring() {
        let configFile = configService.paths.codexHome.appendingPathComponent("config.toml")
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + 15,
            repeating: 15,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            let configuration = CodexConfigService.configurationSignature(at: configFile)
            DispatchQueue.main.async { [weak self] in
                self?.handleRuntimeTick(configuration)
            }
        }
        timer.resume()
        runtimeMonitorTimer = timer

        let descriptor = open(configService.paths.codexHome.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .global(qos: .utility)
        )
        watcher.setEventHandler { [weak self] in
            let configuration = CodexConfigService.configurationSignature(
                at: configFile
            )
            DispatchQueue.main.async { [weak self] in
                self?.handleRuntimeTick(configuration)
            }
        }
        watcher.setCancelHandler {
            close(descriptor)
        }
        watcher.resume()
        configurationWatcher = watcher
    }

    private func handleRuntimeTick(_ configuration: CodexConfigurationSignature?) {
        let reconciledHistory = TaskBridge.reconcileHistory()
        if reconciledHistory != launchHistory {
            launchHistory = reconciledHistory
        }
        if configuration != lastCodexConfiguration {
            lastCodexConfiguration = configuration
            reconcileActiveProfileFromCodex()
        }
        guard !proxy.isReady else { return }
        do {
            try proxy.ensureReady()
            try synchronizeRuntime()
            statusMessage = "API Plus 本机路由已自动恢复"
        } catch {
            statusMessage = "路由异常，正在自动重试"
        }
    }

    private func currentCodexConfiguration() -> CodexConfigurationSignature? {
        CodexConfigService.configurationSignature(
            at: configService.paths.codexHome.appendingPathComponent("config.toml")
        )
    }

    private func relaunchActiveCodex() throws {
        guard let profile = activeProfile else { return }
        _ = try launcher.launch(
            profile: profile,
            paths: configService.paths,
            workingDirectory: profile.workspacePath ?? workingDirectory,
            apiKey: try apiKey(for: profile)
        )
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
        statusMessage = "操作未完成"
    }

    deinit {
        runtimeMonitorTimer?.cancel()
        configurationWatcher?.cancel()
        proxy.stop()
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
