#if os(iOS)
import SwiftUI

/// 1件の終了済みセッションを日時、時間、走行距離、終了理由で示す、詳細へ遷移する一覧行です。
struct IOSConnectionHistoryVehicleSessionsRow: View {
    /// 表示する終了済みセッションです。
    let session: ConnectionSession

    /// 取得元端末と終了理由を整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 状態アイコン、日時、終了理由、取得元、バッジ、計測値を描画します。
    ///
    /// 責務: 1件の終了済みセッションを日時、時間、走行距離、終了理由を持つ一覧行へ配置します。
    var body: some View {
        HStack(spacing: 13) {
            if session.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                WarningTriangleIcon(size: 19)
            }
            details
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label(measurementFormatter.durationText(measurementFormatter.sessionDuration(session)), systemImage: "clock")
                Label(measurementFormatter.distanceText(session.recordedDistanceKilometers), systemImage: "road.lanes")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 日時、終了理由、取得元端末、保管状態バッジの並びです。
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text(LocalizedStringKey(textFormatter.endReasonKey(session.endReason)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.status == .completed ? Color.secondary : Color.orange)
            Label(textFormatter.acquisitionDeviceText(session), systemImage: "laptopcomputer.and.iphone")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                IOSConnectionHistoryVehicleSessionsRawStatusBadge(
                    badge: ConnectionHistoryRawStatusBadge(cloudState: session.rawLogSummary.cloudState)
                )
                IOSConnectionHistoryVehicleSessionsRawStatusBadge(
                    badge: ConnectionHistoryRawStatusBadge(localState: session.rawLogSummary.localState)
                )
            }
        }
    }
}
#endif
