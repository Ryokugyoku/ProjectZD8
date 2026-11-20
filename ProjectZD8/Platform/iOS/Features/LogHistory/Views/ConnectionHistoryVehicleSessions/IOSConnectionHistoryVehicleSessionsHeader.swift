#if os(iOS)
import SwiftUI

/// 車両別一覧の上部で、総件数、総時間、総走行距離、中断件数を示す概要です。
struct IOSConnectionHistoryVehicleSessionsHeader: View {
    /// 表示する車両別履歴集計です。見つからない時は `nil` で、何も描画しません。
    let group: ConnectionHistoryVehicleGroup?

    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 幅に応じて1行または2行で集計値を並べます。
    ///
    /// 責務: 1件の車両グループを一覧上部の件数と警告の概要へ配置します。
    var body: some View {
        if let group {
            ViewThatFits(in: .horizontal) {
                HStack {
                    totalPill(group)
                    durationPill(group)
                    distancePill(group)
                    if group.interruptedCount > 0 { IOSConnectionHistoryWarningBadge(count: group.interruptedCount) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        totalPill(group)
                        if group.interruptedCount > 0 { IOSConnectionHistoryWarningBadge(count: group.interruptedCount) }
                    }
                    HStack {
                        durationPill(group)
                        distancePill(group)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 総件数のピルを返します。
    ///
    /// 責務: 1件の車両グループのセッション件数を要約ピルへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 総件数の要約ピル。
    private func totalPill(_ group: ConnectionHistoryVehicleGroup) -> some View {
        IOSConnectionHistorySummaryPill(value: "\(group.sessionCount)", titleKey: "history.summary.total", color: .primary)
    }

    /// 総時間のピルを返します。
    ///
    /// 責務: 1件の車両グループの総走行時間を要約ピルへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 総時間の要約ピル。
    private func durationPill(_ group: ConnectionHistoryVehicleGroup) -> some View {
        IOSConnectionHistorySummaryPill(
            value: measurementFormatter.durationText(group.totalDuration),
            titleKey: "history.summary.duration",
            color: .cyan
        )
    }

    /// 総走行距離のピルを返します。
    ///
    /// 責務: 1件の車両グループの総走行距離を要約ピルへ変換します。
    /// - Parameter group: 表示する車両別履歴集計。
    /// - Returns: 総走行距離の要約ピル。
    private func distancePill(_ group: ConnectionHistoryVehicleGroup) -> some View {
        IOSConnectionHistorySummaryPill(
            value: measurementFormatter.distanceText(group.totalDistanceKilometers),
            titleKey: "history.summary.distance",
            color: .mint
        )
    }
}
#endif
