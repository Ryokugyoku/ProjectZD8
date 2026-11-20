#if os(iOS)
import SwiftUI

/// 車種専用PIDを標準PIDから区別して並べる区画です。
struct IOSLiveTelemetryPanelVehicleSpecificSection: View {
    /// 表示する車種専用PIDサンプルです。
    let samples: [OBDPIDSample]
    /// 見出しの横に示す車両型式です。ない時はバッジを出しません。
    let modelCode: String?
    /// PID説明の表示要求を通知するクロージャです。
    let onHelp: (OBDPIDSample) -> Void

    /// 見出し、型式バッジ、小型カードの格子を描画します。
    ///
    /// 責務: 車種専用PIDサンプルを枠付きの区画へ配置します。
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.vehicleSectionCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: IOSLiveTelemetryPanelMetrics.sectionContentSpacing) {
            HStack {
                IOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.brz", symbol: "car.side.fill")
                Spacer()
                if let modelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
            }
            LazyVGrid(columns: columns, spacing: IOSLiveTelemetryPanelMetrics.cardSpacing) {
                ForEach(samples) { sample in
                    IOSLiveTelemetryPanelCompactCard(sample: sample, isVehicleSpecific: true) { onHelp(sample) }
                }
            }
        }
        .padding(IOSLiveTelemetryPanelMetrics.vehicleSectionPadding)
        .background(.thinMaterial, in: shape)
        .overlay { shape.stroke(Color.cyan.opacity(IOSLiveTelemetryPanelMetrics.vehicleSectionStrokeOpacity)) }
    }

    /// 小型カードを画面幅に合わせて並べる列です。
    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: IOSLiveTelemetryPanelMetrics.vehicleSectionCardMinWidth),
                spacing: IOSLiveTelemetryPanelMetrics.cardSpacing
            ),
        ]
    }
}
#endif
