#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードで、判定の範囲についての注記(車速なし・範囲外・指定なし)を並べます。
struct MacOSSessionLogAnalysisRoadRegulationNotices: View {
    /// 表示する注記(表示順)です。
    let notices: [SessionRoadRegulationReviewNotice]
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 注記を情報のアイコン付きの小さな文字で縦に並べます。
    ///
    /// 責務: 注記ごとの文言キーを `LocalizedStringKey` に包んで描きます。注記が無ければ何も描きません。
    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
                ForEach(notices) { notice in
                    Label(LocalizedStringKey(notice.textKey), systemImage: "info.circle")
                        .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
