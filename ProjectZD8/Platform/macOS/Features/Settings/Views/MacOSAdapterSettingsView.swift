#if os(macOS)
import SwiftUI

/// 「アダプター」タブ: 既定アダプター・探索結果・探索失敗。
struct MacOSAdapterSettingsView: View {
    let state: DeviceConnectionState
    let send: (DeviceConnectionAction) -> Void

    var body: some View {
        Form {
            Section {
                if let adapter = state.defaultAdapter {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                                Text(verbatim: adapter.displayName)
                                Text(adapter.transport.macOSNameKey).font(InsightTypography.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: adapter.transport.macOSSymbol)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            send(.defaultAdapterCleared)
                        } label: {
                            Text("settings.adapter.clear")
                        }
                    }
                } else {
                    Text("settings.adapter.none").foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.adapter.default")
            }

            Section {
                if case .failed(let error) = state.discovery {
                    InlineBanner(.error, message: Text(LocalizedStringKey(error.localizationKey)))
                }
                if state.adapters.isEmpty {
                    Text(state.discovery == .discovering ? "settings.adapter.searching" : "settings.adapter.empty")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.adapters) { adapter in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                                Text(verbatim: adapter.displayName)
                                if let detail = adapter.detail {
                                    Text(verbatim: detail).font(InsightTypography.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: adapter.transport.macOSSymbol)
                        }
                        Spacer()
                        if state.defaultAdapter?.id == adapter.id {
                            StatusBadge(Text("device.picker.default"), tone: .active)
                        } else {
                            Button {
                                send(.defaultAdapterSelected(adapter))
                            } label: {
                                Text("device.picker.setDefault")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("settings.adapter.discovered")
                    Spacer()
                    if state.discovery == .discovering { ProgressView().controlSize(.small) }
                    Button {
                        send(.discoverRequested)
                    } label: {
                        Label("device.picker.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.discovery == .discovering)
                }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
