import Foundation

enum HealthCheckState {
    case passed
    case warning
    case failed

    var label: String {
        switch self {
        case .passed: "通过"
        case .warning: "注意"
        case .failed: "未通过"
        }
    }
}

struct HealthCheckItem {
    let title: String
    let state: HealthCheckState
    let detail: String
}

struct HealthCheckReport {
    let items: [HealthCheckItem]
    let checkedAt: Date

    var summary: String {
        let failed = items.filter { $0.state == .failed }.count
        let warnings = items.filter { $0.state == .warning }.count
        if failed > 0 { return "启动前检查：\(failed) 项未通过" }
        if warnings > 0 { return "启动前检查：已完成，\(warnings) 项需注意" }
        return "启动前检查：全部通过"
    }
}

enum HealthCheckService {
    static func check(
        profile: ProviderProfile,
        workingDirectory: String,
        apiKey: String?
    ) async -> HealthCheckReport {
        var items: [HealthCheckItem] = []
        let hasKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        do {
            try profile.validate(requireStoredKey: true, hasStoredKey: hasKey)
            items.append(HealthCheckItem(title: "配置", state: .passed, detail: "Responses API 配置有效"))
        } catch {
            items.append(HealthCheckItem(title: "配置", state: .failed, detail: error.localizedDescription))
        }

        if profile.authenticationMode.needsKey {
            items.append(
                HealthCheckItem(
                    title: "凭据",
                    state: hasKey ? .passed : .failed,
                    detail: hasKey ? "API Key 已保存在钥匙串" : "请先保存 API Key"
                )
            )
        } else {
            items.append(HealthCheckItem(title: "凭据", state: .passed, detail: "此本地服务不需要 API Key"))
        }

        let workspaceExists = FileManager.default.fileExists(atPath: workingDirectory)
        items.append(
            HealthCheckItem(
                title: "工作目录",
                state: workspaceExists ? .passed : .failed,
                detail: workspaceExists ? "目录可用" : "目录不存在，请重新选择"
            )
        )

        guard items.allSatisfy({ $0.state != .failed }) else {
            return HealthCheckReport(items: items, checkedAt: Date())
        }

        items.append(contentsOf: await checkAPI(profile: profile, apiKey: apiKey))
        return HealthCheckReport(items: items, checkedAt: Date())
    }

    private static func checkAPI(
        profile: ProviderProfile,
        apiKey: String?
    ) async -> [HealthCheckItem] {
        guard let baseURL = URL(string: profile.baseURL) else {
            return [
                HealthCheckItem(
                    title: "API 连接",
                    state: .failed,
                    detail: "API Base URL 无效；请检查协议、域名和 /v1 路径"
                )
            ]
        }
        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if let apiKey, profile.authenticationMode.needsKey {
            switch profile.authenticationMode {
            case .bearer:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .customHeader:
                request.setValue(apiKey, forHTTPHeaderField: profile.authenticationHeader)
            case .none:
                break
            }
        }

        do {
            let (data, response) = try await BoundedHTTPClient.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .failed,
                        detail: "服务未返回 HTTP 响应；请检查代理或 Base URL"
                    )
                ]
            }
            switch response.statusCode {
            case 200 ..< 300:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .passed,
                        detail: "模型目录可访问（HTTP \(response.statusCode)）"
                    ),
                    modelCheck(profile: profile, data: data)
                ]
            case 401, 403:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .failed,
                        detail: "密钥无效或权限不足（HTTP \(response.statusCode)）；请重新保存密钥并确认账户权限"
                    )
                ]
            case 404, 405:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .warning,
                        detail: "服务可达，但未提供 GET /models；请确认 Base URL 是否需要 /v1"
                    ),
                    HealthCheckItem(
                        title: "模型",
                        state: .warning,
                        detail: "无法自动确认 \(profile.model)，启动后由 Responses API 最终验证"
                    )
                ]
            case 429:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .warning,
                        detail: "触发速率或余额限制（HTTP 429）；请检查额度或稍后重试"
                    )
                ]
            case 500 ..< 600:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .warning,
                        detail: "服务暂时不可用（HTTP \(response.statusCode)）；建议稍后重新检查"
                    )
                ]
            default:
                return [
                    HealthCheckItem(
                        title: "API 连接",
                        state: .failed,
                        detail: "服务返回 HTTP \(response.statusCode)；请检查地址、认证方式和服务商文档"
                    )
                ]
            }
        } catch let error as URLError {
            return [
                HealthCheckItem(
                    title: "API 连接",
                    state: .failed,
                    detail: networkErrorDetail(error)
                )
            ]
        } catch {
            return [
                HealthCheckItem(
                    title: "API 连接",
                    state: .failed,
                    detail: error.localizedDescription
                )
            ]
        }
    }

    private static func modelCheck(profile: ProviderProfile, data: Data) -> HealthCheckItem {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            return HealthCheckItem(
                title: "模型",
                state: .warning,
                detail: "模型目录格式无法识别；启动后由 Responses API 最终验证 \(profile.model)"
            )
        }
        let modelIDs = Set(rows.compactMap { row in
            (row["id"] as? String) ?? (row["model"] as? String)
        })
        if modelIDs.contains(profile.model) {
            return HealthCheckItem(
                title: "模型",
                state: .passed,
                detail: "\(profile.model) 已在服务商模型目录中"
            )
        }
        return HealthCheckItem(
            title: "模型",
            state: .warning,
            detail: "目录中未找到 \(profile.model)；请核对模型 ID 后再启动"
        )
    }

    private static func networkErrorDetail(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "连接超时；请检查网络、代理或服务商状态"
        case .cannotFindHost, .dnsLookupFailed:
            return "无法解析服务域名；请检查 Base URL 或 DNS"
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return "无法连接服务；请检查网络、代理和 Base URL"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "TLS 安全连接失败；请检查服务商证书"
        default:
            return "无法连接服务：\(error.localizedDescription)"
        }
    }
}
