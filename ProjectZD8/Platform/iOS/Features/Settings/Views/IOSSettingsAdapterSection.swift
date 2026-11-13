#if os(iOS)
import SwiftUI

/// 既定のアダプターの現在値・探索・設定・解除のセクションです。
struct IOSSettingsAdapterSection: View {
    let state: DeviceConnectionState
    let send: (DeviceConnectionAction) -> Void

    var body: some View {
        Section {
            if let adapter = state.defaultAdapter {
                LabeledContent("settings.adapter.current") {
                    VStack(alignment: .trailing) {
                        Text(verbatim: adapter.displayName)
                        Text(LocalizedStringKey(adapter.transport.iosNameKey))
                            .font(InsightTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("settings.adapter.clear", role: .destructive) { send(.defaultAdapterCleared) }
            } else {
                Text("settings.adapter.none").foregroundStyle(.secondary)
            }
            Button {
                send(.discoverRequested)
            } label: {
                Label("device.discovery.refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.discovery == .discovering)
            IOSAdapterListContent(state: state, send: send) { send(.defaultAdapterSelected($0)) }
        } header: {
            Text("settings.adapter.header")
        } footer: {
            Text("settings.adapter.footer")
        }
    }
}
#endif
