import Foundation

enum ProviderPreset: String, Codable, CaseIterable, Identifiable {
    case openAI
    case generic
    case cctq
    case cctqSol
    case cctqTerra
    case cctqLuna
    case ollama
    case lmStudio
    case mistral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI API"
        case .generic: "自定义兼容 API"
        case .cctq: "CCTQ Codex"
        case .cctqSol: "CCTQ GPT-5.6 Sol"
        case .cctqTerra: "CCTQ GPT-5.6 Terra"
        case .cctqLuna: "CCTQ GPT-5.6 Luna"
        case .ollama: "Ollama（本地）"
        case .lmStudio: "LM Studio（本地）"
        case .mistral: "Mistral API"
        }
    }

    var icon: String {
        switch self {
        case .openAI: "sparkles"
        case .generic: "network"
        case .cctq, .cctqSol, .cctqTerra, .cctqLuna: "network"
        case .ollama, .lmStudio: "desktopcomputer"
        case .mistral: "bolt.horizontal"
        }
    }
}

enum AuthenticationMode: String, Codable, CaseIterable, Identifiable {
    case bearer
    case customHeader
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bearer: "Bearer API Key"
        case .customHeader: "自定义请求头"
        case .none: "无需密钥"
        }
    }

    var needsKey: Bool { self != .none }
}

struct ProviderProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var preset: ProviderPreset
    var baseURL: String
    var model: String
    var wireAPI: String
    var authenticationMode: AuthenticationMode
    var authenticationHeader: String

    init(
        id: UUID = UUID(),
        name: String,
        preset: ProviderPreset,
        baseURL: String,
        model: String,
        wireAPI: String = "responses",
        authenticationMode: AuthenticationMode,
        authenticationHeader: String = "api-key"
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.wireAPI = wireAPI
        self.authenticationMode = authenticationMode
        self.authenticationHeader = authenticationHeader
    }

    var providerID: String {
        "api_" + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func template(_ preset: ProviderPreset) -> ProviderProfile {
        switch preset {
        case .openAI:
            ProviderProfile(
                name: "OpenAI API",
                preset: .openAI,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-5.4",
                authenticationMode: .bearer
            )
        case .generic:
            ProviderProfile(
                name: "自定义 API",
                preset: .generic,
                baseURL: "https://example.com/v1",
                model: "your-model-id",
                authenticationMode: .bearer
            )
        case .cctq:
            ProviderProfile(
                name: "cctq_codex",
                preset: .cctq,
                baseURL: "https://www.cctq.ai/v1",
                model: "gpt-5.5",
                authenticationMode: .bearer
            )
        case .cctqSol:
            ProviderProfile(
                name: "CCTQ GPT-5.6 Sol",
                preset: .cctqSol,
                baseURL: "https://www.cctq.ai/v1",
                model: "gpt-5.6-sol",
                authenticationMode: .bearer
            )
        case .cctqTerra:
            ProviderProfile(
                name: "CCTQ GPT-5.6 Terra",
                preset: .cctqTerra,
                baseURL: "https://www.cctq.ai/v1",
                model: "gpt-5.6-terra",
                authenticationMode: .bearer
            )
        case .cctqLuna:
            ProviderProfile(
                name: "CCTQ GPT-5.6 Luna",
                preset: .cctqLuna,
                baseURL: "https://www.cctq.ai/v1",
                model: "gpt-5.6-luna",
                authenticationMode: .bearer
            )
        case .ollama:
            ProviderProfile(
                name: "Ollama",
                preset: .ollama,
                baseURL: "http://localhost:11434/v1",
                model: "qwen3-coder",
                authenticationMode: .none
            )
        case .lmStudio:
            ProviderProfile(
                name: "LM Studio",
                preset: .lmStudio,
                baseURL: "http://localhost:1234/v1",
                model: "local-model",
                authenticationMode: .none
            )
        case .mistral:
            ProviderProfile(
                name: "Mistral API",
                preset: .mistral,
                baseURL: "https://api.mistral.ai/v1",
                model: "devstral-latest",
                authenticationMode: .bearer
            )
        }
    }

    mutating func applyPreset(_ preset: ProviderPreset) {
        let replacement = Self.template(preset)
        self.preset = preset
        name = replacement.name
        baseURL = replacement.baseURL
        model = replacement.model
        wireAPI = replacement.wireAPI
        authenticationMode = replacement.authenticationMode
        authenticationHeader = replacement.authenticationHeader
    }
}

enum ProfileValidationError: LocalizedError {
    case emptyName
    case invalidBaseURL
    case emptyModel
    case unsupportedWireAPI
    case emptyAuthenticationHeader
    case missingKey

    var errorDescription: String? {
        switch self {
        case .emptyName: "请填写配置名称。"
        case .invalidBaseURL: "API Base URL 必须是有效的 http 或 https 地址。"
        case .emptyModel: "请填写模型 ID。"
        case .unsupportedWireAPI: "当前 Codex CLI 仅支持 Responses 协议。"
        case .emptyAuthenticationHeader: "请填写认证请求头名称。"
        case .missingKey: "这个配置需要 API Key，请先保存到钥匙串。"
        }
    }
}

extension ProviderProfile {
    func validate(requireStoredKey: Bool, hasStoredKey: Bool) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.emptyName
        }
        guard let components = URLComponents(string: baseURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw ProfileValidationError.invalidBaseURL
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.emptyModel
        }
        guard wireAPI == "responses" else {
            throw ProfileValidationError.unsupportedWireAPI
        }
        if authenticationMode == .customHeader,
           authenticationHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileValidationError.emptyAuthenticationHeader
        }
        if requireStoredKey, authenticationMode.needsKey, !hasStoredKey {
            throw ProfileValidationError.missingKey
        }
    }
}
