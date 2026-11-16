import SwiftUI

/// 記録を終えた時点の走行時間です。開始〜終了の固定値で、タイマーは進みません。
struct RecordingSessionLiveActivityEndedDurationText: View {
    /// 走行時間(秒)です。
    let seconds: TimeInterval

    /// 整形した走行時間を等幅数字で描きます。
    var body: some View {
        Text(verbatim: RecordingSessionLiveActivityDurationFormatter.string(seconds: seconds))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(RecordingSessionLiveActivityMetrics.endedMinimumScaleFactor)
    }
}
