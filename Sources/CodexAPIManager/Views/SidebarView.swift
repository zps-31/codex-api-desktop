import SwiftUI

struct SidebarView: View {
    let store: ProfileStore

    var body: some View {
        List(selection: Bindable(store).selection) {
            Section("API 配置") {
                ForEach(store.profiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.preset.icon)
                            .foregroundStyle(store.activeProfileID == profile.id ? .green : .secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(profile.name).lineLimit(1)
                                if store.activeProfileID == profile.id {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                }
                            }
                            Text(profile.model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("复制配置") { store.duplicateSelected() }
                        Divider()
                        Button("删除", role: .destructive) { store.deleteSelected() }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ProviderPreset.allCases) { preset in
                        Button {
                            store.addProfile(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("添加 API 配置")

                Button {
                    store.deleteSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedProfile == nil)
                .help("删除所选配置")
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
    }
}
