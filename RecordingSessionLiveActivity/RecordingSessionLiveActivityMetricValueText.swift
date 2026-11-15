import SwiftUI

/// 1項目の計測値と単位です。未取得なら既定の「未取得」文言を描きます。
struct RecordingSessionLiveActivityMetricValueText: View {
    /// 計測項目の種類です。単位の文言を決めます。
    let kind: RecordingSessionLiveActivityMetricKind
    /// 表示する計測値です。
    let metric: RecordingSessionActivityAttributes.Metric

    /// 整形済みの数値と単位、または「未取得」を描きます。
    var body: some View {
        if let value = RecordingSessionLiveActivityMetricFormatter.formattedValue(of: metric) {
            HStack(alignment: .firstTextBaseline, spacing: RecordingSessionLiveActivityMetrics.unitSpacing) {
                Text(verbatim: value)
                    .monospacedDigit()
                Text(LocalizedStringKey(kind.unitKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else {
            Text(LocalizedStringKey(RecordingSessionActivityAttributes.unavailableMetricKey))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
