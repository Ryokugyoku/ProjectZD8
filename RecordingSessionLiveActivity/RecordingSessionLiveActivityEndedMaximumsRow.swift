import SwiftUI

/// 終了表示の車速・回転数・スロットル開度の最大値を、横いっぱいに大きく並べた行です。
struct RecordingSessionLiveActivityEndedMaximumsRow: View {
    /// 項目ごとの最大値です。
    let summary: RecordingSessionActivityAttributes.EndedSummary

    /// 項目ごとに見出しと最大値を等幅で描きます。
    var body: some View {
        HStack(alignment: .top, spacing: RecordingSessionLiveActivityMetrics.endedMetricSpacing) {
            ForEach(RecordingSessionLiveActivityMetricKind.allCases, id: \.self) { kind in
                VStack(spacing: RecordingSessionLiveActivityMetrics.metricLabelSpacing) {
                    Text(LocalizedStringKey(kind.labelKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RecordingSessionLiveActivityMetricValueText(kind: kind, metric: kind.maximum(in: summary))
                        .font(.title.weight(.bold))
                        .minimumScaleFactor(RecordingSessionLiveActivityMetrics.endedMinimumScaleFactor)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
