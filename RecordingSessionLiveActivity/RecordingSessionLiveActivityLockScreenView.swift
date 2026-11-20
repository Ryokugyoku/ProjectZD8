import SwiftUI
import WidgetKit

/// ロック画面(と通知センター)に出す記録中セッションの表示です。音楽再生表示に近い広さで、写真・車両名・状態・経過時間・計測値・[切断]を並べます。
struct RecordingSessionLiveActivityLockScreenView: View {
    /// Live Activityの最新の表示内容です。
    let state: RecordingSessionActivityAttributes.ContentState
    /// 記録中の表示か、更新が止まった表示かです。
    let mode: RecordingSessionLiveActivityDisplayMode

    /// 見出し・計測値・フッターを縦に配置します。
    var body: some View {
        VStack(spacing: RecordingSessionLiveActivityMetrics.sectionSpacing) {
            HStack(spacing: RecordingSessionLiveActivityMetrics.headerSpacing) {
                RecordingSessionLiveActivityVehiclePhotoView(
                    fileName: state.vehiclePhotoFileName,
                    size: RecordingSessionLiveActivityMetrics.photoSize
                )
                RecordingSessionLiveActivityTitleView(state: state, mode: mode)
                Spacer(minLength: 0)
                RecordingSessionLiveActivityElapsedTimerText(startedAt: state.startedAt)
                    .font(.title3.weight(.semibold))
            }
            RecordingSessionLiveActivityMetricsRow(state: state)
            RecordingSessionLiveActivityFooterView(receivedResponseCount: state.receivedResponseCount)
        }
        .padding(RecordingSessionLiveActivityMetrics.contentPadding)
    }
}
