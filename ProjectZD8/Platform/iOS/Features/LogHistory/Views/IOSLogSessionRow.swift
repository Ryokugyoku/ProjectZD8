#if os(iOS)
import SwiftUI

/// 一覧の1セッションの行です。開始日時・時間・距離・終了理由・状態バッジを示します。
struct IOSLogSessionRow: View {
    let row: LogHistorySessionRow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    Text(row.startedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(InsightTypography.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: InsightSpacing.sm)
                    badges
                }
                HStack(spacing: InsightSpacing.sm) {
                    if row.isRecording {
                        Text("logs.row.inProgress")
                    } else if let duration = row.durationText {
                        Text(verbatim: duration)
                    }
                    if let distance = row.distanceText {
                        Text(verbatim: "·")
                        Text(verbatim: distance)
                    }
                    Text(verbatim: "·")
                    Text("logs.row.samples \(row.sampleCount)")
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
                if let key = row.endReasonKey, row.wasInterrupted {
                    Label(LocalizedStringKey(key), systemImage: "exclamationmark.triangle.fill")
                        .font(InsightTypography.caption)
                        .foregroundStyle(InsightPalette.warning)
                }
            }
            .frame(minHeight: InsightSpacing.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var badges: some View {
        HStack(spacing: InsightSpacing.xs) {
            if row.isRecording { StatusBadge(Text("drive.phase.recording"), tone: .active, symbol: "record.circle") }
            if row.isDemo { StatusBadge(Text("drive.demo"), tone: .warning) }
            if row.rawLocation == .iCloudOnly {
                StatusBadge(Text(LocalizedStringKey(row.rawLocation.nameKey)), tone: .neutral, symbol: "icloud")
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
#endif
