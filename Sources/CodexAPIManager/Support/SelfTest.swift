import Foundation

enum SelfTest {
    static func run() throws {
        try expect(
            TOMLEscaping.string("a\\b\"c\n") == "a\\\\b\\\"c\\n",
            "TOML escaping"
        )

        let generic = ProviderProfile.template(.generic)
        try expect(generic.providerID.hasPrefix("api_"), "provider prefix")
        try expect(!generic.providerID.contains("-"), "provider key characters")

        let local = ProviderProfile.template(.ollama)
        try local.validate(requireStoredKey: true, hasStoredKey: false)
        try expect(
            ProfileStore.isAvailable(local, hasStoredKey: false),
            "keyless local profile availability"
        )

        let remote = ProviderProfile.template(.openAI)
        try expect(
            !ProfileStore.isAvailable(remote, hasStoredKey: false),
            "remote profile requires a key"
        )
        let isolatedHome = URL(
            fileURLWithPath: "/tmp/codex-api-plus/api-home",
            isDirectory: true
        )
        let accountHome = KeychainService.resolvedUserHome(
            accountDirectory: "/Users/example",
            fallback: isolatedHome
        )
        try expect(
            accountHome.path == "/Users/example",
            "account home overrides isolated process HOME"
        )
        try expect(
            KeychainService.loginKeychainURL(home: accountHome).path
                == "/Users/example/Library/Keychains/login.keychain-db",
            "login Keychain path"
        )
        try expect(
            KeychainService.legacyServices.contains(
                "com.zps.codex-api-manager.api-keys"
            ),
            "legacy Keychain service compatibility"
        )
        try expect(
            KeychainService.parseKeychainList(
                "    \"/Users/example/Library/Keychains/login.keychain-db\"\n"
            ) == ["/Users/example/Library/Keychains/login.keychain-db"],
            "Keychain search-list parsing"
        )
        do {
            try remote.validate(requireStoredKey: true, hasStoredKey: false)
            throw SelfTestError.failed("remote key validation")
        } catch ProfileValidationError.missingKey {
            // Expected.
        }

        let service = try CodexConfigService.defaultPaths()
        try expect(service.desktopHomeDirectory.lastPathComponent == "api-home", "desktop home path")
        try expect(service.desktopDataDirectory.lastPathComponent == "desktop-data", "desktop data path")
        try expect(service.desktopLogFile.lastPathComponent == "codex-desktop-api.log", "desktop log path")
        try expect(service.modelCatalogFile.lastPathComponent == "model-catalog.json", "model catalog path")
        try expect(service.authFile.lastPathComponent == "auth.json", "auth path")
        try expect(service.desktopPIDFile.lastPathComponent == "codex-desktop-api.pid", "desktop pid path")
        try expect(ProviderProfile.template(.cctq).baseURL == "https://www.cctq.ai/v1", "CCTQ base URL")
        try expect(ProviderProfile.template(.cctq).model == "gpt-5.5", "CCTQ model")
        try expect(
            !ProviderPreset.creationCases.contains(where: {
                [.cctq, .cctqSol, .cctqTerra, .cctqLuna].contains($0)
            }),
            "CCTQ presets hidden from creation menu"
        )
        let duplicateSource = ProviderProfile.template(.openAI)
        let duplicate = duplicateSource.duplicated(
            existingNames: [duplicateSource.name, "\(duplicateSource.name) 副本"]
        )
        try expect(duplicate.id != duplicateSource.id, "duplicate gets a new ID")
        try expect(duplicate.name == "OpenAI API 副本 2", "duplicate gets a unique name")
        try expect(ProviderProfile.template(.cctqSol).model == "gpt-5.6-sol", "GPT-5.6 Sol model")
        try expect(ProviderProfile.template(.cctqTerra).model == "gpt-5.6-terra", "GPT-5.6 Terra model")
        try expect(ProviderProfile.template(.cctqLuna).model == "gpt-5.6-luna", "GPT-5.6 Luna model")
        try expect(
            ProviderProfile.template(.openAI).workScenario == .development,
            "default work scenario"
        )
        try expect(
            ProviderProfile.template(.openAI).taskBudgetUSD
                == WorkScenario.development.recommendedTaskBudgetUSD,
            "default task budget"
        )
        try expect(WorkScenario.codeReview.sandboxMode == "read-only", "review sandbox")
        try expect(WorkScenario.deepDebug.modelReasoningEffort == "xhigh", "debug reasoning")
        try verifySecretFreeAuthFile()
        try verifyIsolatedDesktopEnvironment()
        try verifyPortableWorkspaceResolution()
        try verifyLogRotation()
        try verifyEscapedModelConfiguration()
        try verifyTaskHistoryReconciliation()
        try verifySessionUsageReading()
        try verifyApplicationLocation()
        try expect(!ProxyHeaderPolicy.forwardsRequest("Accept-Encoding"), "request decompression policy")
        try expect(!ProxyHeaderPolicy.forwardsResponse("Content-Encoding"), "response decompression policy")
        try expect(ProxyHeaderPolicy.forwardsResponse("Content-Type"), "response content type")
        try verifyChunkedRequestParsing()
        try verifyMalformedRequestRejection()
        try verifyUpstreamURLConstruction()
        try verifyCredentialTransportValidation()

        let legacyProfile = """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "name": "Legacy",
          "preset": "openAI",
          "baseURL": "https://api.openai.com/v1",
          "model": "gpt-5.4",
          "wireAPI": "responses",
          "authenticationMode": "bearer",
          "authenticationHeader": "api-key"
        }
        """
        let decodedLegacy = try JSONDecoder().decode(
            ProviderProfile.self,
            from: Data(legacyProfile.utf8)
        )
        try expect(decodedLegacy.workScenario == .development, "legacy scenario migration")
        try expect(
            decodedLegacy.taskBudgetUSD == WorkScenario.development.recommendedTaskBudgetUSD,
            "legacy task budget migration"
        )
        try expect(decodedLegacy.workspacePath == nil, "legacy workspace migration")

        let legacyTask = """
        {
          "schemaVersion": 2,
          "taskID": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "projectName": "Legacy",
          "profileName": "Old API",
          "providerName": "CCTQ",
          "model": "legacy-model",
          "scenario": "普通开发",
          "startedAt": "2026-07-11T12:00:00Z"
        }
        """
        let taskDecoder = JSONDecoder()
        taskDecoder.dateDecodingStrategy = .iso8601
        let decodedTask = try taskDecoder.decode(
            TaskBridgeRecord.self,
            from: Data(legacyTask.utf8)
        )
        try expect(decodedTask.processID == nil, "legacy task PID migration")
        try expect(decodedTask.profileID == nil, "legacy task profile migration")
        var customRelay = ProviderProfile.template(.generic)
        customRelay.baseURL = "https://BotCF.com/v1"
        try expect(
            TaskBridge.billingProvider(for: customRelay) == "origin:https://botcf.com",
            "custom billing provider origin"
        )
        customRelay.baseURL = "https://cctq.ai.example.com/v1"
        try expect(
            TaskBridge.billingProvider(for: customRelay)
                == "origin:https://cctq.ai.example.com",
            "billing provider lookalike domain"
        )
        let proxy = APIProxyServer()
        try proxy.ensureReady(port: 0)
        try expect(proxy.isReady, "loopback router startup")
        proxy.stop()
    }

    private static func verifySecretFreeAuthFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: codexHome,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: codexHome.path
        )
        let existingProfiles = root.appendingPathComponent("profiles.json")
        let existingLog = root.appendingPathComponent("desktop.log")
        let existingLauncher = root.appendingPathComponent("launcher.command")
        for file in [existingProfiles, existingLog, existingLauncher] {
            try Data().write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: file.path
            )
        }
        let paths = RuntimePaths(
            supportDirectory: root,
            profilesFile: root.appendingPathComponent("profiles.json"),
            codexHome: codexHome,
            activeProfileFile: root.appendingPathComponent("active-profile"),
            activeAuthModeFile: root.appendingPathComponent("active-auth-mode"),
            workingDirectoryFile: root.appendingPathComponent("working-directory"),
            launcherFile: root.appendingPathComponent("launcher.command"),
            desktopHomeDirectory: root.appendingPathComponent("api-home"),
            desktopDataDirectory: root.appendingPathComponent("desktop-data"),
            desktopLogFile: root.appendingPathComponent("desktop.log"),
            modelCatalogFile: root.appendingPathComponent("model-catalog.json"),
            authFile: codexHome.appendingPathComponent("auth.json"),
            desktopPIDFile: root.appendingPathComponent("desktop.pid")
        )
        let service = CodexConfigService(paths: paths)
        try service.prepareDirectories()
        try service.writeEmptyAuthFile()

        for directory in [
            paths.supportDirectory,
            paths.codexHome,
            paths.desktopHomeDirectory,
            paths.desktopDataDirectory
        ] {
            let directoryAttributes = try FileManager.default.attributesOfItem(
                atPath: directory.path
            )
            try expect(
                (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
                    == 0o700,
                "private runtime directory permissions"
            )
        }
        for file in [paths.profilesFile, paths.desktopLogFile] {
            let fileAttributes = try FileManager.default.attributesOfItem(
                atPath: file.path
            )
            try expect(
                (fileAttributes[.posixPermissions] as? NSNumber)?.intValue
                    == 0o600,
                "existing private runtime file permissions"
            )
        }
        let launcherAttributes = try FileManager.default.attributesOfItem(
            atPath: paths.launcherFile.path
        )
        try expect(
            (launcherAttributes[.posixPermissions] as? NSNumber)?.intValue
                == 0o700,
            "existing launcher permissions"
        )
        let data = try Data(contentsOf: paths.authFile)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
        try expect(object?.isEmpty == true, "secret-free auth file")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: paths.authFile.path
        )
        try expect(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "auth file permissions"
        )
    }

    private static func verifyIsolatedDesktopEnvironment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = RuntimePaths(
            supportDirectory: root,
            profilesFile: root.appendingPathComponent("profiles.json"),
            codexHome: root.appendingPathComponent("codex-home"),
            activeProfileFile: root.appendingPathComponent("active-profile"),
            activeAuthModeFile: root.appendingPathComponent("active-auth-mode"),
            workingDirectoryFile: root.appendingPathComponent("working-directory"),
            launcherFile: root.appendingPathComponent("launcher.command"),
            desktopHomeDirectory: root.appendingPathComponent("api-home"),
            desktopDataDirectory: root.appendingPathComponent("desktop-data"),
            desktopLogFile: root.appendingPathComponent("desktop.log"),
            modelCatalogFile: root.appendingPathComponent("model-catalog.json"),
            authFile: root.appendingPathComponent("codex-home/auth.json"),
            desktopPIDFile: root.appendingPathComponent("desktop.pid")
        )
        let environment = CodexDesktopLauncher.isolatedEnvironment(
            inherited: [
                "HOME": "/Users/official",
                "PATH": "/usr/bin:/bin",
                "CODEX_API_KEY": "must-not-leak",
                "OPENAI_API_KEY": "must-not-leak",
                "OPENAI_BASE_URL": "https://must-not-leak.example"
            ],
            paths: paths
        )
        try expect(
            environment["HOME"] == paths.desktopHomeDirectory.path,
            "isolated HOME"
        )
        try expect(
            environment["CFFIXED_USER_HOME"] == paths.desktopHomeDirectory.path,
            "isolated Core Foundation home"
        )
        try expect(
            environment["CODEX_HOME"] == paths.codexHome.path,
            "isolated CODEX_HOME"
        )
        try expect(
            environment["XDG_CONFIG_HOME"]?.hasPrefix(paths.desktopHomeDirectory.path) == true,
            "isolated XDG config"
        )
        try expect(environment["PATH"] == "/usr/bin:/bin", "preserved PATH")
        try expect(environment["CODEX_API_KEY"] == nil, "removed Codex API key")
        try expect(environment["OPENAI_API_KEY"] == nil, "removed OpenAI API key")
        try expect(environment["OPENAI_BASE_URL"] == nil, "removed OpenAI base URL")
    }

    private static func verifyPortableWorkspaceResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("new-home", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let project = documents.appendingPathComponent("Portable Project", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: project,
            withIntermediateDirectories: true
        )

        try expect(
            WorkspacePathResolver.defaultWorkingDirectory(home: home) == documents.path,
            "portable Documents fallback"
        )
        try expect(
            WorkspacePathResolver.resolve(
                "/Users/old-user/Documents/Portable Project",
                home: home
            ) == project.path,
            "portable workspace user rebasing"
        )

        let codex = documents.appendingPathComponent("Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try expect(
            WorkspacePathResolver.resolve(
                "/Users/old-user/Documents/Missing",
                home: home
            ) == codex.path,
            "portable Codex fallback"
        )
        try expect(
            WorkspacePathResolver.resolve(
                "/Volumes/Temporarily Offline/Project",
                home: home
            ) == "/Volumes/Temporarily Offline/Project",
            "preserved external workspace"
        )
    }

    private static func verifyLogRotation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let log = root.appendingPathComponent("desktop.log")
        let previous = root.appendingPathComponent("desktop.previous.log")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 9 * 1_024 * 1_024).write(to: log)

        try CodexDesktopLauncher.prepareLogFile(at: log)
        let attributes = try FileManager.default.attributesOfItem(atPath: log.path)
        let previousAttributes = try FileManager.default.attributesOfItem(
            atPath: previous.path
        )
        try expect(
            (attributes[.size] as? NSNumber)?.intValue == 0,
            "rotated active log"
        )
        try expect(
            (previousAttributes[.size] as? NSNumber)?.intValue
                == 4 * 1_024 * 1_024,
            "bounded previous log"
        )
        try expect(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "private log permissions"
        )
    }

    private static func verifyEscapedModelConfiguration() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = "provider/model\"variant"
        try "model = \"\(TOMLEscaping.string(model))\"\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        try expect(
            CodexConfigService.configuredModel(at: file) == model,
            "escaped model configuration"
        )
    }

    private static func verifyTaskHistoryReconciliation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let record = TaskBridgeRecord(
            schemaVersion: 3,
            taskID: UUID(),
            projectName: "Fixture",
            profileName: "Test",
            providerName: "Test",
            model: "test-model",
            scenario: "普通开发",
            startedAt: Date(timeIntervalSince1970: 100),
            billingProvider: nil,
            taskBudgetUSD: nil,
            endedAt: nil,
            status: "running",
            processID: Int32.max,
            workingDirectory: "/tmp",
            profileID: UUID()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: directory.appendingPathComponent(TaskBridge.activeTaskFilename)
        )

        let now = Date(timeIntervalSince1970: 200)
        let history = TaskBridge.reconcileHistory(in: directory, now: now)
        try expect(history.first?.status == "finished", "finished task status")
        try expect(history.first?.endedAt == now, "finished task time")
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        try expect(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
                == 0o700,
            "private task bridge directory permissions"
        )
        let historyAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(
                TaskBridge.historyFilename
            ).path
        )
        try expect(
            (historyAttributes[.posixPermissions] as? NSNumber)?.intValue
                == 0o600,
            "private task history permissions"
        )
        try expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    TaskBridge.activeTaskFilename
                ).path
            ),
            "active task cleanup"
        )
    }

    private static func verifySessionUsageReading() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":12345},"last_token_usage":{"total_tokens":678},"model_context_window":200000}}}
        """
        try Data(fixture.utf8).write(to: directory.appendingPathComponent("rollout.jsonl"))
        let snapshot = SessionUsageService.latest(in: directory)
        try expect(snapshot?.totalTokens == 12_345, "current session usage")
        try expect(snapshot?.lastRequestTokens == 678, "last request usage")
        try expect(snapshot?.contextWindow == 200_000, "context window usage")

        let monitor = SessionUsageMonitor()
        try expect(
            monitor.latest(in: directory)?.totalTokens == 12_345,
            "session monitor initial value"
        )
        let updatedFixture = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":23456},"last_token_usage":{"total_tokens":789},"model_context_window":200000}}}
        """
        try Data(updatedFixture.utf8).write(
            to: directory.appendingPathComponent("rollout.jsonl")
        )
        try expect(
            monitor.latest(in: directory)?.totalTokens == 23_456,
            "session monitor refresh"
        )
    }

    private static func verifyApplicationLocation() throws {
        try expect(
            !InstalledApplicationLocator.supportsExecutableArchitectures(
                [NSNumber(value: NSBundleExecutableArchitectureARM64)],
                hostArchitectures: [NSBundleExecutableArchitectureX86_64]
            ),
            "incompatible application architecture rejection"
        )
        try expect(
            InstalledApplicationLocator.supportsExecutableArchitectures(
                [
                    NSNumber(value: NSBundleExecutableArchitectureARM64),
                    NSNumber(value: NSBundleExecutableArchitectureX86_64)
                ],
                hostArchitectures: [NSBundleExecutableArchitectureX86_64]
            ),
            "universal application architecture acceptance"
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = root.appendingPathComponent("Portable Fixture.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: macOS,
            withIntermediateDirectories: true
        )
        let executable = macOS.appendingPathComponent("PortableFixture")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.portable-fixture",
            "CFBundleExecutable": "PortableFixture",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let located = InstalledApplicationLocator.applicationURL(
            bundleIdentifiers: ["com.example.portable-fixture"],
            names: ["Portable Fixture.app"],
            additionalDirectories: [root]
        )
        try expect(located?.path == app.path, "portable application location")
        try expect(
            !InstalledApplicationLocator.isValidApplication(
                at: app,
                acceptedBundleIdentifiers: ["com.example.other"]
            ),
            "application bundle ID validation"
        )
    }

    private static func verifyChunkedRequestParsing() throws {
        let request = """
        POST /v1/responses HTTP/1.1\r
        Host: 127.0.0.1\r
        Transfer-Encoding: chunked\r
        Content-Type: application/json\r
        \r
        8\r
        {"model"\r
        B\r
        :"fixture"}\r
        0\r
        \r

        """
        let parsed = HTTPProxyRequest.parse(Data(request.utf8))
        try expect(parsed?.method == "POST", "chunked request method")
        let object = parsed.flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? [String: String] }
        try expect(object?["model"] == "fixture", "chunked request body")
    }

    private static func verifyMalformedRequestRejection() throws {
        let negativeLength = "POST /v1/responses HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
        try expect(HTTPProxyRequest.parse(Data(negativeLength.utf8)) == nil, "negative content length")
        let hugeChunk = "POST /v1/responses HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFFFFFF\r\n"
        try expect(HTTPProxyRequest.parse(Data(hugeChunk.utf8)) == nil, "overflowing chunk size")
    }

    private static func verifyUpstreamURLConstruction() throws {
        let withBaseQuery = APIProxyServer.upstreamURL(
            baseURL: "https://example.com/v1?api-version=2026-07-01",
            requestPath: "/v1/responses?stream=true"
        )
        try expect(withBaseQuery?.path == "/v1/responses", "upstream response path")
        try expect(
            withBaseQuery?.query == "api-version=2026-07-01",
            "preserved base URL query"
        )
        let withRequestQuery = APIProxyServer.upstreamURL(
            baseURL: "https://example.com/v1",
            requestPath: "/v1/responses?stream=true"
        )
        try expect(withRequestQuery?.query == "stream=true", "preserved request query")
    }

    private static func verifyCredentialTransportValidation() throws {
        var insecure = ProviderProfile.template(.generic)
        insecure.baseURL = "http://example.com/v1"
        insecure.authenticationMode = .bearer
        do {
            try insecure.validate(requireStoredKey: false, hasStoredKey: true)
            throw SelfTestError.failed("insecure credential transport")
        } catch ProfileValidationError.insecureCredentialTransport {}

        var protectedHeader = ProviderProfile.template(.generic)
        protectedHeader.authenticationMode = .customHeader
        protectedHeader.authenticationHeader = "Content-Length"
        do {
            try protectedHeader.validate(requireStoredKey: false, hasStoredKey: true)
            throw SelfTestError.failed("protected authentication header")
        } catch ProfileValidationError.invalidAuthenticationHeader {}

        var embeddedCredentials = ProviderProfile.template(.generic)
        embeddedCredentials.baseURL = "https://user:password@example.com/v1"
        do {
            try embeddedCredentials.validate(requireStoredKey: false, hasStoredKey: true)
            throw SelfTestError.failed("embedded URL credentials")
        } catch ProfileValidationError.embeddedURLCredentials {}

        var injectedModel = ProviderProfile.template(.generic)
        injectedModel.model = "model\"\napproval_policy=\"never"
        do {
            try injectedModel.validate(requireStoredKey: false, hasStoredKey: true)
            throw SelfTestError.failed("model config injection")
        } catch ProfileValidationError.invalidModel {}
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw SelfTestError.failed(name) }
    }
}

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let name): "自检失败：\(name)"
        }
    }
}
