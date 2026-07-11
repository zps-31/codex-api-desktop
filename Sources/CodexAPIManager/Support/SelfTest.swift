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

        let remote = ProviderProfile.template(.openAI)
        do {
            try remote.validate(requireStoredKey: true, hasStoredKey: false)
            throw SelfTestError.failed("remote key validation")
        } catch ProfileValidationError.missingKey {
            // Expected.
        }

        let service = try CodexConfigService.defaultPaths()
        try expect(service.desktopDataDirectory.lastPathComponent == "desktop-data", "desktop data path")
        try expect(service.desktopLogFile.lastPathComponent == "codex-desktop-api.log", "desktop log path")
        try expect(service.modelCatalogFile.lastPathComponent == "model-catalog.json", "model catalog path")
        try expect(service.authFile.lastPathComponent == "auth.json", "auth path")
        try expect(service.desktopPIDFile.lastPathComponent == "codex-desktop-api.pid", "desktop pid path")
        try expect(ProviderProfile.template(.cctq).baseURL == "https://www.cctq.ai/v1", "CCTQ base URL")
        try expect(ProviderProfile.template(.cctq).model == "gpt-5.5", "CCTQ model")
        try expect(ProviderProfile.template(.cctqSol).model == "gpt-5.6-sol", "GPT-5.6 Sol model")
        try expect(ProviderProfile.template(.cctqTerra).model == "gpt-5.6-terra", "GPT-5.6 Terra model")
        try expect(ProviderProfile.template(.cctqLuna).model == "gpt-5.6-luna", "GPT-5.6 Luna model")
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
