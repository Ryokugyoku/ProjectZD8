#if os(iOS)
import SwiftUI

/// iOS設定画面で、交通規制データの取得状況のまとめと「データを管理」ボタンを描画します。
///
/// まとめの文言は `RoadRegulationSettingsTextFormatter` が作り、この型は描画と管理画面を開く通知だけを行います。
struct IOSSettingsRoadRegulationCard: View {
    /// 値を差し込む文言に使うロケールです。
    @Environment(\.locale) private var locale

    /// 取得状況のまとめです。
    let summary: RoadRegulationSettingsSummary
    /// 「データを管理」が押されたことを通知するクロージャです。
    let manage: () -> Void

    /// まとめと管理ボタンを持つカードを提供します。
    ///
    /// 責務: 取得済みの県の数と最も古い基準月、取り込み中ならその印を描画し、管理画面を開く操作を通知します。
    var body: some View {
        IOSSettingsCard(
            eyebrow: "road_regulation.settings.eyebrow",
            title: "road_regulation.settings.title",
            description: "road_regulation.settings.description",
            systemImage: "signpost.right.fill"
        ) {
            VStack(alignment: .leading, spacing: IOSSettingsMetrics.routeRecordingContentSpacing) {
                summaryRow
                Button(action: manage) {
                    Text("road_regulation.settings.manage")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("ios-settings-road-regulation-manage")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-settings-road-regulation")
    }

    /// まとめの文言と、取り込み中なら進行中の印を並べた行です。
    private var summaryRow: some View {
        HStack(spacing: IOSSettingsMetrics.routeRecordingNoticeSpacing) {
            if summary.isImporting {
                ProgressView()
                    .accessibilityLabel(Text("road_regulation.status.importing"))
            }
            Text(verbatim: RoadRegulationSettingsTextFormatter(locale: locale).summaryText(summary))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("ios-settings-road-regulation-summary")
    }
}
#endif
