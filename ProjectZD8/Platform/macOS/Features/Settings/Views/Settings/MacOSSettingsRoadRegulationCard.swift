#if os(macOS)
import SwiftUI

/// macOS設定画面で、交通規制データの取得状況のまとめと「データを管理」ボタンを描画します。
///
/// まとめの文言は `RoadRegulationSettingsTextFormatter` が作り、この型は描画と管理画面を開く通知だけを行います。
struct MacOSSettingsRoadRegulationCard: View {
    /// 値を差し込む文言に使うロケールです。
    @Environment(\.locale) private var locale

    /// 取得状況のまとめです。
    let summary: RoadRegulationSettingsSummary
    /// 「データを管理」が押されたことを通知するクロージャです。
    let manage: () -> Void
    /// ウインドウ寸法に応じた拡大率を持つ寸法です。
    let metrics: MacOSAppShellMetrics

    /// まとめと管理ボタンを持つカードを提供します。
    ///
    /// 責務: 取得済みの県の数と最も古い基準月、取り込み中ならその印を描画し、管理画面を開く操作を通知します。
    var body: some View {
        MacOSSettingsCard(
            eyebrow: "road_regulation.settings.eyebrow",
            title: "road_regulation.settings.title",
            description: "road_regulation.settings.description",
            systemImage: "signpost.right.fill",
            metrics: metrics
        ) {
            HStack(spacing: MacOSRoadRegulationDataMetrics.cardContentSpacing * metrics.scale) {
                summaryRow
                Spacer(minLength: 0)
                Button("road_regulation.settings.manage", action: manage)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("macos-settings-road-regulation-manage")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-settings-road-regulation")
    }

    /// まとめの文言と、取り込み中なら進行中の印を並べた行です。
    private var summaryRow: some View {
        HStack(spacing: MacOSRoadRegulationDataMetrics.progressSpacing * metrics.scale) {
            if summary.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("road_regulation.status.importing"))
            }
            Text(verbatim: RoadRegulationSettingsTextFormatter(locale: locale).summaryText(summary))
                .font(.system(size: MacOSRoadRegulationDataMetrics.cardSummaryFontSize * metrics.scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("macos-settings-road-regulation-summary")
    }
}
#endif
