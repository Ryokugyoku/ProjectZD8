#if os(iOS)
import SwiftUI

/// 探索状態に応じたアダプター一覧の中身です。ドライブの選択シートと設定で共有します。
struct IOSAdapterListContent: View {
    let state: DeviceConnectionState
    let send: (DeviceConnectionAction) -> Void
    /// 行が選ばれた時の処理です。
    let onSelect: (AdapterDescriptor) -> Void

    var body: some View {
        if case .failed(let error) = state.discovery {
            InlineBanner(
                .error,
                title: Text("device.discovery.failure.title"),
                message: Text(LocalizedStringKey(error.localizationKey)),
                action: InsightAction(Text("device.discovery.retry")) { send(.discoverRequested) }
            )
        }
        if state.discovery == .discovering {
            HStack(spacing: InsightSpacing.md) {
                ProgressView()
                Text("device.discovery.searching").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        ForEach(state.adapters) { adapter in
            IOSAdapterRow(adapter: adapter, isDefault: adapter.id == state.defaultAdapter?.id) {
                onSelect(adapter)
            }
        }
        if state.adapters.isEmpty, state.discovery == .completed {
            Text("device.discovery.empty")
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
