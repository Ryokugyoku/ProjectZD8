#if os(macOS)
import SwiftUI

/// 回転数と車速を優先した主要値を大きなカードで並べる区画です。
struct MacOSLiveTelemetryPanelPrimaryDashboard: View {
    /// 表示する主要PIDサンプル(最大2件)です。
    let samples: [OBDPIDSample]
    /// 応答中のPID数です。接続中で1件以上ある時だけ値を持ちます。
    let respondingPIDCount: Int?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// PID説明を表示中のPIDです。表示していなければ `nil` です。
    let helpSampleID: OBDPIDSample.ID?
    /// PID説明の表示要求を通知するクロージャです。
    let onHelpRequested: (OBDPIDSample) -> Void
    /// PID説明を閉じたことを通知するクロージャです。
    let onHelpDismissed: (OBDPIDSample) -> Void

    /// 見出し、応答中のPID数、主要値カードを描画します。
    ///
    /// 責務: 主要PIDサンプルを見出し付きのカードの格子へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(alignment: .firstTextBaseline) {
                MacOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.now", symbol: "speedometer", scale: scale)
                Spacer(minLength: 8 * scale)
                if let respondingPIDCount {
                    respondingCount(respondingPIDCount)
                }
            }
            LazyVGrid(columns: columns, spacing: 16 * scale) {
                ForEach(samples) { sample in
                    MacOSLiveTelemetryPanelPrimaryCard(
                        sample: sample,
                        scale: scale,
                        isShowingHelp: helpSampleID == sample.id,
                        onHelpRequested: { onHelpRequested(sample) },
                        onHelpDismissed: { onHelpDismissed(sample) }
                    )
                }
            }
        }
    }

    /// 主要値カードをウインドウ幅に合わせて並べる列です。
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 300 * scale), spacing: 16 * scale)]
    }

    /// 応答中のPID数を小さく示します。
    ///
    /// 責務: 1件のPID数を数値と説明の短い表示へ変換します。
    /// - Parameter count: 応答中のPID数。
    /// - Returns: 見出しの右に置く小さな表示。
    private func respondingCount(_ count: Int) -> some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .foregroundStyle(.cyan)
            Text(count, format: .number)
                .font(.system(size: 15 * scale, weight: .bold, design: .rounded).monospacedDigit())
            Text("telemetry.status.responding_count")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11 * scale, weight: .semibold))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
#endif
