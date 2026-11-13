#if os(macOS)
import SwiftUI

/// セッション一覧の1行。選択状態・記録中・中断・デモ・Raw の所在を示す。
struct MacOSLogSessionRow: View {
    let row: LogHistorySessionRow
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: InsightSpacing.md) {
                VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                    HStack(spacing: InsightSpacing.sm) {
                        Text(row.startedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(InsightTypography.sectionTitle)
                        if row.isRecording { StatusBadge(Text("history.badge.recording"), tone: .critical, symbol: "record.circle") }
                        if row.isDemo { StatusBadge(Text("drive.badge.demo"), tone: .warning, symbol: "sparkles") }
                        if row.wasInterrupted { StatusBadge(Text("history.badge.interrupted"), tone: .warning, symbol: "exclamationmark.triangle") }
                    }
                    HStack(spacing: InsightSpacing.md) {
                        if let duration = row.durationText { Label(duration, systemImage: "clock") }
                        if let distance = row.distanceText { Label(distance, systemImage: "road.lanes") }
                        Label {
                            Text("history.row.samples \(row.sampleCount)")
                        } icon: {
                            Image(systemName: "waveform.path.ecg")
                        }
                        if let key = row.endReasonKey { Text(LocalizedStringKey(key)) }
                    }
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: InsightSpacing.md)
                VStack(alignment: .trailing, spacing: InsightSpacing.xs) {
                    Text(LocalizedStringKey(row.rawLocation.nameKey)).font(InsightTypography.footnote)
                    Text(LocalizedStringKey(row.uploadState.nameKey)).font(InsightTypography.footnote)
                }
                .foregroundStyle(.secondary)
            }
            .padding(InsightSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                    .fill(isSelected ? InsightPalette.accent.opacity(0.14) : InsightPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? InsightPalette.accent : InsightPalette.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
