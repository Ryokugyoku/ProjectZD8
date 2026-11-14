#if os(macOS)
import SwiftUI

/// 車両別履歴ヘッダーの集計表示です。
struct MacOSConnectionHistoryVehicleSessionsSummary: View {
    /// 表示する車両別履歴集計です。見つからない場合はゼロ値を使用します。
    let group: ConnectionHistoryVehicleGroup?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// セッション数、総時間、総走行距離、中断件数を並べます。
    ///
    /// 責務: 1件の車両グループを車両別履歴ヘッダー用の集計列へ配置します。
    var body: some View {
        HStack(spacing: 18 * scale) {
            MacOSConnectionHistoryMetric(value: "\(group?.sessionCount ?? 0)", titleKey: "history.vehicle.sessions", scale: scale)
            MacOSConnectionHistoryMetric(
                value: measurementFormatter.durationText(group?.totalDuration ?? 0),
                titleKey: "history.summary.duration",
                scale: scale
            )
            MacOSConnectionHistoryMetric(
                value: measurementFormatter.distanceText(group?.totalDistanceKilometers),
                titleKey: "history.summary.distance",
                scale: scale
            )
            if let count = group?.interruptedCount, count > 0 { MacOSConnectionHistoryWarningBadge(count: count, scale: scale) }
        }
    }
}
#endif
