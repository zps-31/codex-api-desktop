import SwiftUI

struct ContentView: View {
    let store: ProfileStore

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            if let selection = store.selection,
               let index = store.profiles.firstIndex(where: { $0.id == selection }) {
                ProviderDetailView(profile: $store.profiles[index], store: store)
            } else {
                ContentUnavailableView(
                    "选择一个 API 配置",
                    systemImage: "server.rack",
                    description: Text("从左侧选择配置，或使用 + 新建供应商。")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.saveProfiles()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    if let profile = store.selectedProfile { store.activate(profile) }
                } label: {
                    Label("设为当前", systemImage: "checkmark.circle")
                }
                .disabled(store.selectedProfile == nil)

                Button {
                    store.launchSelected()
                } label: {
                    Label("启动 Codex API", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.selectedProfile == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.activeProfile == nil ? Color.secondary : Color.green)
                    .frame(width: 7, height: 7)
                Text(store.statusMessage.isEmpty ? activeSummary : store.statusMessage)
                    .lineLimit(1)
                Spacer()
                Button("打开官方 Codex") { store.openOfficialCodex() }
                    .buttonStyle(.link)
                Text("数据隔离：\(store.runtimeDirectory)")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(store.runtimeDirectory)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(.bar)
        }
        .alert("Codex API 管理器", isPresented: $store.showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage)
        }
    }

    private var activeSummary: String {
        if let profile = store.activeProfile {
            return "当前：\(profile.name) / \(profile.model)"
        }
        return "尚未激活 API 配置"
    }
}
