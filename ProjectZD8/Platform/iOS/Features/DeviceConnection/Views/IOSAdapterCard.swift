#if os(iOS)
import SwiftUI

/// ドライブ画面の既定アダプターのカードです。検出・未検出・未設定を状態から示します。
struct IOSAdapterCard: View {
    let state: DeviceConnectionState
    let onChoose: () -> Void

    var body: some View {
        InsightCard(title: Text("drive.adapter.title")) {
            if let adapter = state.defaultAdapter {
                HStack(spacing: InsightSpacing.md) {
                    Image(systemName: adapter.transport.iosSymbolName)
                        .font(.title2)
                        .foregroundStyle(InsightPalette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                        Text(verbatim: adapter.displayName).font(InsightTypography.body)
                        Text(LocalizedStringKey(adapter.transport.iosNameKey))
                            .font(InsightTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: InsightSpacing.sm)
                    detectionBadge
                }
                Button(action: onChoose) { Text("drive.adapter.change").frame(maxWidth: .infinity) }
                    .buttonStyle(.insightSecondary)
            } else {
                Text("drive.adapter.none")
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                Button(action: onChoose) { Text("drive.adapter.choose").frame(maxWidth: .infinity) }
                    .buttonStyle(.insightSecondary)
            }
        }
    }

    @ViewBuilder
    private var detectionBadge: some View {
        switch state.discovery {
        case .discovering:
            StatusBadge(Text("drive.adapter.searching"), tone: .active)
        case .completed:
            if state.isDefaultAdapterDetected {
                StatusBadge(Text("drive.adapter.detected"), tone: .positive)
            } else {
                StatusBadge(Text("drive.adapter.notDetected"), tone: .warning)
            }
        case .idle, .failed:
            StatusBadge(Text("drive.adapter.notChecked"), tone: .neutral)
        }
    }
}
#endif
