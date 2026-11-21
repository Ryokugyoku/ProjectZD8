#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」で、判定の範囲についての注記(車速なし・範囲外・指定なし)を並べます。
struct IOSSessionLogAnalysisRoadRegulationNotices: View {
    /// 表示する注記(表示順)です。
    let notices: [SessionRoadRegulationReviewNotice]

    /// 注記を情報のアイコン付きの小さな文字で並べます。
    ///
    /// 責務: 注記ごとに文言キーを描画します。注記が無ければ何も描きません。
    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.noticeSpacing) {
                ForEach(notices) { notice in
                    Label(LocalizedStringKey(notice.textKey), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
