#if os(iOS)
import SwiftUI

/// 回転数と車速を優先した主要値を2列の大きなカードで並べる区画です。
struct IOSLiveTelemetryPanelPrimaryDashboard: View {
    /// 表示する主要PIDサンプル(最大2件)です。
    let samples: [OBDPIDSample]
    /// 応答中のPID数です。接続中で1件以上ある時だけ値を持ちます。
    let respondingPIDCount: Int?
    /// PID説明の表示要求を通知するクロージャです。
    let onHelp: (OBDPIDSample) -> Void

    /// 見出し、応答中のPID数、主要値カードを描画します。
    ///
    /// 責務: 主要PIDサンプルを見出し付きの2列のカードへ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSLiveTelemetryPanelMetrics.sectionContentSpacing) {
            HStack(alignment: .firstTextBaseline) {
                IOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.now", symbol: "speedometer")
                Spacer(minLength: 8)
                if let respondingPIDCount {
                    respondingCount(respondingPIDCount)
                }
            }
            LazyVGrid(columns: columns, spacing: IOSLiveTelemetryPanelMetrics.cardSpacing) {
                ForEach(samples) { sample in
                    IOSLiveTelemetryPanelPrimaryCard(sample: sample) { onHelp(sample) }
                }
            }
        }
    }

    /// 主要値カードを並べる2列です。
    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: IOSLiveTelemetryPanelMetrics.cardSpacing),
            GridItem(.flexible(), spacing: IOSLiveTelemetryPanelMetrics.cardSpacing),
        ]
    }

    /// 応答中のPID数を小さく示します。
    ///
    /// 責務: 1件のPID数を数値と説明の短い表示へ変換します。
    /// - Parameter count: 応答中のPID数。
    /// - Returns: 見出しの右に置く小さな表示。
    private func respondingCount(_ count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .foregroundStyle(.cyan)
            Text(count, format: .number)
                .font(.subheadline.monospacedDigit().weight(.bold))
            Text("telemetry.status.responding_count")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
#endif
