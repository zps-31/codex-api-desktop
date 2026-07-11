import AppKit
import SwiftUI

struct ProviderDetailView: View {
    @Binding var profile: ProviderProfile
    let store: ProfileStore
    @State private var keyDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                configurationCard
                credentialCard
                workspaceCard
                compatibilityNote
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(profile.name)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: profile.preset.icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name).font(.title2.bold())
                Text("\(profile.model) · \(profile.baseURL)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            if store.activeProfileID == profile.id {
                Label("当前使用", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var configurationCard: some View {
        GroupBox("供应商与模型") {
            Form {
                Picker("配置模板", selection: Binding(
                    get: { profile.preset },
                    set: { profile.applyPreset($0); keyDraft = "" }
                )) {
                    ForEach(ProviderPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                TextField("配置名称", text: $profile.name)
                TextField("API Base URL", text: $profile.baseURL)
                    .textContentType(.URL)
                TextField("模型 ID", text: $profile.model)
                LabeledContent("接口协议") {
                    Text("Responses API")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var credentialCard: some View {
        GroupBox("API 凭据") {
            Form {
                Picker("认证方式", selection: $profile.authenticationMode) {
                    ForEach(AuthenticationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if profile.authenticationMode == .customHeader {
                    TextField("请求头名称", text: $profile.authenticationHeader)
                }

                if profile.authenticationMode.needsKey {
                    SecureField(
                        store.hasKey(for: profile) ? "已保存；输入新值可替换" : "粘贴 API Key",
                        text: $keyDraft
                    )
                    HStack {
                        Label(
                            store.hasKey(for: profile) ? "密钥已保存在 macOS 钥匙串" : "尚未保存密钥",
                            systemImage: store.hasKey(for: profile) ? "lock.fill" : "lock.open"
                        )
                        .foregroundStyle(store.hasKey(for: profile) ? .green : .secondary)
                        Spacer()
                        if store.hasKey(for: profile) {
                            Button("移除", role: .destructive) {
                                store.clearKey(for: profile)
                            }
                        }
                        Button("保存密钥") {
                            store.saveKey(keyDraft, for: profile)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Text("适用于 Ollama、LM Studio 或其他不需要认证的本地服务。")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var workspaceCard: some View {
        GroupBox("启动位置") {
            HStack(spacing: 10) {
                TextField("工作目录", text: Bindable(store).workingDirectory)
                Button("选择…") { chooseDirectory() }
            }
            .padding(10)
        }
    }

    private var compatibilityNote: some View {
        Label {
            Text("Codex CLI 的自定义供应商使用 Responses 协议。第三方服务需要兼容 `/responses`、工具调用与流式输出；仅兼容 Chat Completions 的服务可通过 LiteLLM 等兼容代理接入。")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: store.workingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            store.workingDirectory = url.path
        }
    }
}
