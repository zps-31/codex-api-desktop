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

    static let creationCases: [ProviderPreset] = [
        .openAI,
        .generic,
        .ollama,
        .lmStudio,
        .mistral
    ]

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

enum WorkScenario: String, Codable, CaseIterable, Identifiable {
    case quickTask
    case development
    case deepDebug
    case codeReview
    case learning
    case economical
    case documentation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickTask: "快速任务"
        case .development: "普通开发"
        case .deepDebug: "深度排错"
        case .codeReview: "代码审查"
        case .learning: "学习讲解"
        case .economical: "低成本模式"
        case .documentation: "文档与写作"
        }
    }

    var icon: String {
        switch self {
        case .quickTask: "bolt"
        case .development: "hammer"
        case .deepDebug: "stethoscope"
        case .codeReview: "checklist"
        case .learning: "book.closed"
        case .economical: "leaf"
        case .documentation: "doc.text"
        }
    }

    var summary: String {
        switch self {
        case .quickTask: "适合小修改、明确问题和快速验证；降低推理深度以减少等待。"
        case .development: "适合日常功能开发；允许修改当前工作区并保持较强推理。"
        case .deepDebug: "适合复杂错误和多步骤排查；使用最高推理深度。"
        case .codeReview: "只读检查代码与变更，优先发现风险，不主动修改文件。"
        case .learning: "只读学习与讲解，强调原因、思路、示例和可复习的结论。"
        case .economical: "适合批量简单任务，平衡成本、速度和结果质量。"
        case .documentation: "适合整理说明、README 与学习笔记；允许更新工作区文档。"
        }
    }

    var modelReasoningEffort: String {
        switch self {
        case .development, .codeReview, .learning: "high"
        case .deepDebug: "xhigh"
        case .quickTask, .economical, .documentation: "medium"
        }
    }

    var planReasoningEffort: String {
        switch self {
        case .deepDebug: "xhigh"
        case .development, .codeReview, .learning: "high"
        case .quickTask, .economical, .documentation: "medium"
        }
    }

    var sandboxMode: String {
        switch self {
        case .codeReview, .learning: "read-only"
        case .quickTask, .development, .deepDebug, .economical, .documentation: "workspace-write"
        }
    }

    var recommendedTaskBudgetUSD: Double {
        switch self {
        case .quickTask: 0.25
        case .development: 2
        case .deepDebug: 5
        case .codeReview: 1
        case .learning: 0.75
        case .economical: 0.20
        case .documentation: 0.50
        }
    }
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
    var workScenario: WorkScenario
    var taskBudgetUSD: Double
    var workspacePath: String?

    init(
        id: UUID = UUID(),
        name: String,
        preset: ProviderPreset,
        baseURL: String,
        model: String,
        wireAPI: String = "responses",
        authenticationMode: AuthenticationMode,
        authenticationHeader: String = "api-key",
        workScenario: WorkScenario = .development,
        taskBudgetUSD: Double? = nil,
        workspacePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.wireAPI = wireAPI
        self.authenticationMode = authenticationMode
        self.authenticationHeader = authenticationHeader
        self.workScenario = workScenario
        self.taskBudgetUSD = taskBudgetUSD ?? workScenario.recommendedTaskBudgetUSD
        self.workspacePath = workspacePath
    }

    var providerID: String {
        "api_" + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    var workspaceName: String {
        guard let workspacePath, !workspacePath.isEmpty else { return "未设置项目" }
        return URL(fileURLWithPath: workspacePath, isDirectory: true).lastPathComponent
    }

    func duplicated(existingNames: Set<String>) -> ProviderProfile {
        var copy = self
        copy.id = UUID()
        var candidate = "\(name) 副本"
        var number = 2
        while existingNames.contains(candidate) {
            candidate = "\(name) 副本 \(number)"
            number += 1
        }
        copy.name = candidate
        return copy
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case preset
        case baseURL
        case model
        case wireAPI
        case authenticationMode
        case authenticationHeader
        case workScenario
        case taskBudgetUSD
        case workspacePath
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        preset = try values.decode(ProviderPreset.self, forKey: .preset)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        wireAPI = try values.decodeIfPresent(String.self, forKey: .wireAPI) ?? "responses"
        authenticationMode = try values.decodeIfPresent(
            AuthenticationMode.self,
            forKey: .authenticationMode
        ) ?? .bearer
        authenticationHeader = try values.decodeIfPresent(
            String.self,
            forKey: .authenticationHeader
        ) ?? "api-key"
        workScenario = try values.decodeIfPresent(
            WorkScenario.self,
            forKey: .workScenario
        ) ?? .development
        taskBudgetUSD = try values.decodeIfPresent(Double.self, forKey: .taskBudgetUSD)
            ?? workScenario.recommendedTaskBudgetUSD
        workspacePath = try values.decodeIfPresent(String.self, forKey: .workspacePath)
    }
}

enum ProfileValidationError: LocalizedError {
    case emptyName
    case invalidBaseURL
    case emptyModel
    case invalidModel
    case unsupportedWireAPI
    case emptyAuthenticationHeader
    case missingKey
    case invalidTaskBudget
    case insecureCredentialTransport
    case embeddedURLCredentials
    case invalidAuthenticationHeader

    var errorDescription: String? {
        switch self {
        case .emptyName: "请填写配置名称。"
        case .invalidBaseURL: "API Base URL 必须是有效的 http 或 https 地址。"
        case .emptyModel: "请填写模型 ID。"
        case .invalidModel: "模型 ID 不能包含控制字符，且不能超过 256 个字节。"
        case .unsupportedWireAPI: "当前 Codex CLI 仅支持 Responses 协议。"
        case .emptyAuthenticationHeader: "请填写认证请求头名称。"
        case .missingKey: "这个配置需要 API Key，请先保存到钥匙串。"
        case .invalidTaskBudget: "单任务预算必须是 0 或正数。"
        case .insecureCredentialTransport: "带 API Key 的远程地址必须使用 https；http 仅允许本机地址。"
        case .embeddedURLCredentials: "Base URL 不能包含用户名或密码；凭据必须保存到 macOS 钥匙串。"
        case .invalidAuthenticationHeader: "认证请求头名称无效或属于受保护的网络请求头。"
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
              components.host != nil,
              baseURL.utf8.count <= 2_048,
              components.fragment == nil else {
            throw ProfileValidationError.invalidBaseURL
        }
        guard components.user == nil, components.password == nil else {
            throw ProfileValidationError.embeddedURLCredentials
        }
        let host = components.host?.lowercased() ?? ""
        let loopbackHosts = ["localhost", "127.0.0.1", "::1", "[::1]"]
        if authenticationMode.needsKey, scheme != "https", !loopbackHosts.contains(host) {
            throw ProfileValidationError.insecureCredentialTransport
        }
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            throw ProfileValidationError.emptyModel
        }
        guard modelID == model,
              modelID.utf8.count <= 256,
              !modelID.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ProfileValidationError.invalidModel
        }
        guard wireAPI == "responses" else {
            throw ProfileValidationError.unsupportedWireAPI
        }
        if authenticationMode == .customHeader {
            let header = authenticationHeader.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !header.isEmpty else { throw ProfileValidationError.emptyAuthenticationHeader }
            let allowed = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
            let protected = ["host", "content-length", "connection", "transfer-encoding"]
            guard header.unicodeScalars.allSatisfy(allowed.contains), !protected.contains(header.lowercased()) else {
                throw ProfileValidationError.invalidAuthenticationHeader
            }
        }
        if requireStoredKey, authenticationMode.needsKey, !hasStoredKey {
            throw ProfileValidationError.missingKey
        }
        guard taskBudgetUSD.isFinite, taskBudgetUSD >= 0 else {
            throw ProfileValidationError.invalidTaskBudget
        }
    }
}
