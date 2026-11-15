import SwiftUI

/// 記録開始からの経過時間です。システムのタイマー表示で、Live Activityを更新しなくても進みます。
struct RecordingSessionLiveActivityElapsedTimerText: View {
    /// 記録を開始した時刻です。
    let startedAt: Date

    /// 開始時刻から数え上げるタイマーを等幅数字で描きます。
    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(minWidth: RecordingSessionLiveActivityMetrics.timerMinWidth, alignment: .trailing)
            .accessibilityLabel(Text("live_activity.label.elapsed"))
    }
}
