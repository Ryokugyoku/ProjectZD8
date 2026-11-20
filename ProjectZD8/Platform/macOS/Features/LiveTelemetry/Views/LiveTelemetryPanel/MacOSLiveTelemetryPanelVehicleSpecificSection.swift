#if os(macOS)
import SwiftUI

/// 車種専用PIDを標準PIDから区別して並べる区画です。
struct MacOSLiveTelemetryPanelVehicleSpecificSection: View {
    /// 表示する車種専用PIDサンプルです。
    let samples: [OBDPIDSample]
    /// 見出しの横に示す車両型式です。ない時はバッジを出しません。
    let modelCode: String?
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// PID説明を表示中のPIDです。表示していなければ `nil` です。
    let helpSampleID: OBDPIDSample.ID?
    /// PID説明の表示要求を通知するクロージャです。
    let onHelpRequested: (OBDPIDSample) -> Void
    /// PID説明を閉じたことを通知するクロージャです。
    let onHelpDismissed: (OBDPIDSample) -> Void

    /// 見出し、型式バッジ、小型カードの格子を描画します。
    ///
    /// 責務: 車種専用PIDサンプルを枠付きの区画へ配置します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 23 * scale, style: .continuous)
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack {
                MacOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.brz", symbol: "car.side.fill", scale: scale)
                Spacer()
                if let modelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
            }
            LazyVGrid(columns: columns, spacing: 12 * scale) {
                ForEach(samples) { sample in
                    MacOSLiveTelemetryPanelSampleCard(
                        sample: sample,
                        isVehicleSpecific: true,
                        scale: scale,
                        isShowingHelp: helpSampleID == sample.id,
                        onHelpRequested: { onHelpRequested(sample) },
                        onHelpDismissed: { onHelpDismissed(sample) }
                    )
                }
            }
        }
        .padding(19 * scale)
        .background(.thinMaterial, in: shape)
        .overlay { shape.stroke(Color.cyan.opacity(0.22)) }
    }

    /// 小型カードをウインドウ幅に合わせて並べる列です。
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 205 * scale), spacing: 12 * scale)]
    }
}
#endif
