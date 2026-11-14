#if os(macOS)
import SwiftUI

/// 1台分の終了済み履歴集計を示す、車両別一覧へ遷移可能なカードです。
struct MacOSConnectionHistoryVehicleGroupCard: View {
    /// 表示する車両別履歴集計です。
    let group: ConnectionHistoryVehicleGroup
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 車両名称と表示識別子を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 中断を含む車両で強調に使う色です。
    private var symbolColor: Color { group.interruptedCount > 0 ? Color.orange : Color.accentColor }

    /// 車両情報、件数、総時間、総走行距離、中断警告を描画します。
    ///
    /// 責務: 1件の車両別履歴集計を警告状態付きのカードへ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            HStack(spacing: 12 * scale) {
                Image(systemName: "car.side.fill").font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 48 * scale, height: 48 * scale)
                    .background(symbolColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(textFormatter.vehicleGroupName(group.vehicle))
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded)).lineLimit(1)
                    if let identifier = textFormatter.vehicleIdentifier(group.vehicle) {
                        Text(identifier).font(.system(size: 9.5 * scale, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(.tertiary)
            }
            Divider().opacity(0.55)
            HStack {
                MacOSConnectionHistoryMetric(value: "\(group.sessionCount)", titleKey: "history.vehicle.sessions", scale: scale)
                MacOSConnectionHistoryMetric(
                    value: measurementFormatter.durationText(group.totalDuration),
                    titleKey: "history.summary.duration",
                    scale: scale
                )
                MacOSConnectionHistoryMetric(
                    value: measurementFormatter.distanceText(group.totalDistanceKilometers),
                    titleKey: "history.summary.distance",
                    scale: scale
                )
                Spacer()
                if group.interruptedCount > 0 { MacOSConnectionHistoryWarningBadge(count: group.interruptedCount, scale: scale) }
            }
        }
        .padding(18 * scale).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                .stroke(group.interruptedCount > 0 ? .orange.opacity(0.25) : Color.primary.opacity(0.07))
        }
    }
}
#endif
