#if os(iOS)
import SwiftUI

/// 1分類に含まれる現在値を小型カードで並べる詳細画面です。PID説明のシートもこの画面が持ちます。
struct IOSLiveTelemetryPanelCategoryDetail: View {
    /// 表示するPID分類です。
    let category: OBDPIDCategory
    /// 分類に含まれるPIDサンプル(取得順)です。
    let samples: [OBDPIDSample]
    /// 説明シートへ表示する現在のPIDです。
    @State private var helpSample: OBDPIDSample?

    /// 分類内の全サンプルを縦に並べ、説明シートを接続します。
    ///
    /// 責務: 1件のPID分類の全現在値を、ナビゲーション見出し付きの一覧へ描画します。
    var body: some View {
        ScrollView {
            LazyVStack(spacing: IOSLiveTelemetryPanelMetrics.cardSpacing) {
                ForEach(samples) { sample in
                    IOSLiveTelemetryPanelCompactCard(
                        sample: sample,
                        isVehicleSpecific: LiveTelemetrySampleGroups.isVehicleSpecific(sample)
                    ) {
                        helpSample = sample
                    }
                }
            }
            .padding(IOSLiveTelemetryPanelMetrics.detailPadding)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(category.nameKey))
        .sheet(item: $helpSample) { sample in
            IOSLiveTelemetryPanelHelpSheet(content: LiveTelemetryPIDHelpContent(sample: sample)) {
                helpSample = nil
            }
        }
    }

    /// システムの背景へ控えめなシアンの光を重ねた背景です。
    private var background: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [Color.cyan.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: IOSLiveTelemetryPanelMetrics.detailGlowRadius
            )
        }
    }
}
#endif
