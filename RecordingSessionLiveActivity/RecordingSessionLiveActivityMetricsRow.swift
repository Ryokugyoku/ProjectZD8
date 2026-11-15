import SwiftUI

/// 車速・回転数・スロットル開度を等幅で横に並べた行です。
struct RecordingSessionLiveActivityMetricsRow: View {
    /// Live Activityの最新の表示内容です。各計測値を読みます。
    let state: RecordingSessionActivityAttributes.ContentState

    /// 表示する計測項目ごとに見出しと値を描きます。
    var body: some View {
        HStack(alignment: .top, spacing: RecordingSessionLiveActivityMetrics.metricSpacing) {
            ForEach(RecordingSessionLiveActivityMetricKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: RecordingSessionLiveActivityMetrics.metricLabelSpacing) {
                    Text(LocalizedStringKey(kind.labelKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RecordingSessionLiveActivityMetricValueText(kind: kind, metric: kind.metric(in: state))
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
