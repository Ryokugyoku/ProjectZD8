#if os(macOS)
import SwiftUI

/// ドライブ画面の待機状態で既定アダプターの状態を示すカード。
///
/// 「検出済み」は検出結果(`isDefaultAdapterDetected`)の裏付けがある時だけ表示する。
struct MacOSDefaultAdapterCard: View {
    let state: DeviceConnectionState
    let onChooseAdapter: () -> Void

    var body: some View {
        InsightCard(title: Text("drive.adapter.title")) {
            HStack(spacing: InsightSpacing.md) {
                if let adapter = state.defaultAdapter {
                    Image(systemName: adapter.transport.macOSSymbol)
                        .font(.title2)
                        .foregroundStyle(InsightPalette.accent)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                        Text(verbatim: adapter.displayName).font(InsightTypography.sectionTitle)
                        Text(adapter.transport.macOSNameKey)
                            .font(InsightTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: InsightSpacing.md)
                    detectionBadge
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    Text("drive.adapter.none")
                        .font(InsightTypography.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: InsightSpacing.md)
                }
                Button(action: onChooseAdapter) {
                    Text(state.defaultAdapter == nil ? "drive.adapter.choose" : "drive.adapter.change")
                }
                .buttonStyle(.insightSecondary)
            }
        }
    }

    @ViewBuilder
    private var detectionBadge: some View {
        switch state.discovery {
        case .discovering:
            StatusBadge(Text("drive.adapter.searching"), tone: .active, symbol: "magnifyingglass")
        case .completed:
            if state.isDefaultAdapterDetected {
                StatusBadge(Text("drive.adapter.detected"), tone: .positive, symbol: "checkmark.circle.fill")
            } else {
                StatusBadge(Text("drive.adapter.notDetected"), tone: .warning, symbol: "exclamationmark.triangle.fill")
            }
        case .idle, .failed:
            StatusBadge(Text("drive.adapter.notChecked"), tone: .neutral, symbol: "minus.circle")
        }
    }
}
#endif
