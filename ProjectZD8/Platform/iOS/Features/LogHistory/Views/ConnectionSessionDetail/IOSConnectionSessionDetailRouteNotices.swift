#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細の走行ルートのカードで、注記を縦に並べて表示します。
struct IOSConnectionSessionDetailRouteNotices: View {
    /// 注記のローカライズキー(表示順)です。
    let noticeKeys: [String]

    /// 注記を情報のアイコン付きの小さな文字で並べます。
    ///
    /// 責務: 受け取ったキーの順に注記を描画します。キーが無ければ何も描きません。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSDrivingRouteDetailMetrics.noticeSpacing) {
            ForEach(Array(noticeKeys.enumerated()), id: \.offset) { _, key in
                Label(LocalizedStringKey(key), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
