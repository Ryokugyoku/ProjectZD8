#if os(macOS)
import SwiftUI

/// 分類チップで分類を選び、選んだ分類の全現在値を一覧する区画です。
struct MacOSLiveTelemetryPanelCategoryWorkspace: View {
    /// サンプルの振り分け結果です。
    let groups: LiveTelemetrySampleGroups
    /// 一覧を表示する分類です。表示できる分類へ補正済みの値を受け取ります。
    let selectedCategory: OBDPIDCategory
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// PID説明を表示中のPIDです。表示していなければ `nil` です。
    let helpSampleID: OBDPIDSample.ID?
    /// 分類の選択を通知するクロージャです。
    let onSelectCategory: (OBDPIDCategory) -> Void
    /// PID説明の表示要求を通知するクロージャです。
    let onHelpRequested: (OBDPIDSample) -> Void
    /// PID説明を閉じたことを通知するクロージャです。
    let onHelpDismissed: (OBDPIDSample) -> Void

    /// 見出し、横に並ぶ分類チップ、選択分類の小型カードの格子を描画します。
    ///
    /// 責務: 分類の選択操作と選択分類のサンプル一覧を1つの区画へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            MacOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.all", symbol: "square.grid.2x2", scale: scale)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8 * scale) {
                    ForEach(groups.availableCategories, id: \.self) { category in
                        MacOSLiveTelemetryPanelCategoryButton(
                            category: category,
                            representative: groups.representativeSample(in: category),
                            isSelected: category == selectedCategory,
                            scale: scale,
                            onSelect: { onSelectCategory(category) }
                        )
                    }
                }
            }
            LazyVGrid(columns: columns, spacing: 12 * scale) {
                ForEach(groups.samples(in: selectedCategory)) { sample in
                    MacOSLiveTelemetryPanelSampleCard(
                        sample: sample,
                        isVehicleSpecific: LiveTelemetrySampleGroups.isVehicleSpecific(sample),
                        scale: scale,
                        isShowingHelp: helpSampleID == sample.id,
                        onHelpRequested: { onHelpRequested(sample) },
                        onHelpDismissed: { onHelpDismissed(sample) }
                    )
                }
            }
        }
    }

    /// 小型カードをウインドウ幅に合わせて並べる列です。
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 210 * scale), spacing: 12 * scale)]
    }
}
#endif
