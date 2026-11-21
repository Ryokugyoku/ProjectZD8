#if os(iOS)
import SwiftUI

/// 1台分の終了済み履歴集計を示す、車両別一覧へ遷移可能なカードです。
struct IOSConnectionHistoryVehicleGroupCard: View {
    /// 表示する車両別履歴集計です。
    let group: ConnectionHistoryVehicleGroup

    /// 車両名称を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 車両情報、セッション件数、総時間、総走行距離、中断警告を描画します。
    ///
    /// 責務: 1件の車両別履歴集計を件数、総時間、総走行距離と警告状態を持つカードへ配置します。
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: group.interruptedCount > 0 ? "car.side.fill" : "car.side")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(group.interruptedCount > 0 ? Color.orange : Color.accentColor)
                .frame(width: 50, height: 50)
                .background(
                    (group.interruptedCount > 0 ? Color.orange : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            details
            Spacer(minLength: 4)
            if group.interruptedCount > 0 {
                IOSConnectionHistoryWarningBadge(count: group.interruptedCount)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(17)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(group.interruptedCount > 0 ? .orange.opacity(0.25) : Color.primary.opacity(0.07))
        }
    }

    /// 車両名称、セッション件数、総時間と総走行距離の並びです。
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(textFormatter.vehicleGroupName(group.vehicle))
                .font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
            HStack(spacing: 3) {
                Text(group.sessionCount, format: .number)
                Text("history.vehicle.sessions")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { measurementLabels }
                VStack(alignment: .leading, spacing: 3) { measurementLabels }
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.tertiary)
        }
    }

    /// 総時間と総走行距離のラベルです。親のスタックへ直接並びます。
    @ViewBuilder private var measurementLabels: some View {
        Label(measurementFormatter.durationText(group.totalDuration), systemImage: "clock")
        Label(measurementFormatter.distanceText(group.totalDistanceKilometers), systemImage: "road.lanes")
    }
}
#endif
