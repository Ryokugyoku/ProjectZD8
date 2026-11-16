import SwiftUI

/// ロック画面(と通知センター)に出す、記録終了後の表示です。余白を詰め、走行時間と各種の最大値を大きく横いっぱいに並べます。
/// [切断]ボタンと動くタイマーは出しません。
struct RecordingSessionLiveActivityEndedView: View {
    /// Live Activityの最新の表示内容です。
    let state: RecordingSessionActivityAttributes.ContentState
    /// 走行時間と最大値です。
    let summary: RecordingSessionActivityAttributes.EndedSummary

    /// 見出し・走行時間・最大値を縦に配置します。
    var body: some View {
        VStack(spacing: RecordingSessionLiveActivityMetrics.sectionSpacing) {
            HStack(spacing: RecordingSessionLiveActivityMetrics.headerSpacing) {
                RecordingSessionLiveActivityVehiclePhotoView(
                    fileName: state.vehiclePhotoFileName,
                    size: RecordingSessionLiveActivityMetrics.photoSize
                )
                RecordingSessionLiveActivityEndedTitleView(state: state)
                Spacer(minLength: 0)
                drivingTime
            }
            RecordingSessionLiveActivityEndedMaximumsRow(summary: summary)
        }
        .padding(.horizontal, RecordingSessionLiveActivityMetrics.endedHorizontalPadding)
        .padding(.vertical, RecordingSessionLiveActivityMetrics.endedVerticalPadding)
    }

    /// 走行時間の見出しと大きな固定値です。
    private var drivingTime: some View {
        VStack(alignment: .trailing, spacing: RecordingSessionLiveActivityMetrics.endedDurationSpacing) {
            Text(LocalizedStringKey(RecordingSessionActivityAttributes.drivingTimeLabelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            RecordingSessionLiveActivityEndedDurationText(seconds: summary.drivingSeconds)
                .font(.largeTitle.weight(.bold))
        }
    }
}
