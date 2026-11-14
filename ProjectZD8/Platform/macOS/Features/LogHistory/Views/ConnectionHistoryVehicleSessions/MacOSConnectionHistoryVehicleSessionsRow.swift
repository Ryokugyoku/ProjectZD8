#if os(macOS)
import SwiftUI

/// 1件の終了済みセッションを日時、取得元、保管状態、時間、走行距離、終了理由で示す一覧行です。
struct MacOSConnectionHistoryVehicleSessionsRow: View {
    /// 表示する終了済みセッションです。
    let session: ConnectionSession
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 取得元端末、終了理由、短縮IDを整形します。
    private let textFormatter = ConnectionHistorySessionTextFormatter()
    /// 走行時間と走行距離を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 状態アイコン、日時、バッジ、終了理由、計測値、短縮IDを描画します。
    ///
    /// 責務: 1件の終了済みセッションを詳細画面へ遷移可能な一覧行へ配置します。
    var body: some View {
        HStack(spacing: 14 * scale) {
            if session.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18 * scale))
            } else {
                WarningTriangleIcon(size: 18 * scale)
            }
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
                Label(textFormatter.acquisitionDeviceText(session), systemImage: "laptopcomputer.and.iphone")
                    .font(.system(size: 9.5 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 7 * scale) {
                    MacOSConnectionHistoryVehicleSessionsRawStatusBadge(
                        badge: ConnectionHistoryRawStatusBadge(cloudState: session.rawLogSummary.cloudState),
                        scale: scale
                    )
                    MacOSConnectionHistoryVehicleSessionsRawStatusBadge(
                        badge: ConnectionHistoryRawStatusBadge(localState: session.rawLogSummary.localState),
                        scale: scale
                    )
                }
            }
            .frame(minWidth: 190 * scale, alignment: .leading)
            Text(LocalizedStringKey(textFormatter.endReasonKey(session.endReason)))
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundStyle(session.status == .completed ? Color.secondary : Color.orange)
            Spacer()
            VStack(alignment: .trailing, spacing: 3 * scale) {
                Label(measurementFormatter.durationText(measurementFormatter.sessionDuration(session)), systemImage: "clock")
                Label(measurementFormatter.distanceText(session.recordedDistanceKilometers), systemImage: "road.lanes")
            }
            .font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            Text(textFormatter.shortID(session.id)).font(.system(size: 9 * scale, design: .monospaced)).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right").font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(.tertiary)
        }
        .padding(15 * scale)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15 * scale, style: .continuous))
    }
}
#endif
