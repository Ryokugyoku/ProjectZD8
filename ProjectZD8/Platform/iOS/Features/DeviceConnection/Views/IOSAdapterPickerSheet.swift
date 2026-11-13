#if os(iOS)
import SwiftUI

/// 探索したアダプターを一覧し、既定のアダプターを選ぶシートです。
struct IOSAdapterPickerSheet: View {
    let state: DeviceConnectionState
    let send: (DeviceConnectionAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    IOSAdapterListContent(state: state, send: send) { adapter in
                        send(.defaultAdapterSelected(adapter))
                        onDismiss()
                    }
                } footer: {
                    Text("device.picker.footer")
                }
            }
            .navigationTitle(Text("device.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { send(.discoverRequested) } label: {
                        Label("device.discovery.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.discovery == .discovering)
                }
            }
            .task { send(.discoverRequested) }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
