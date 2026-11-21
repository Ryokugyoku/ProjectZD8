#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、走行ルートに添える注記を表示順に並べます。
struct MacOSConnectionSessionDetailRouteNotices: View {
    /// 注記のローカライズキー(表示順)です。空なら何も描きません。
    let noticeKeys: [String]
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 注記を縦に並べて描画します。
    ///
    /// 責務: 注記ごとに情報のアイコンと文言を1行ずつ描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSDrivingRouteDetailMetrics.noticeSpacing * scale) {
            ForEach(noticeKeys, id: \.self) { key in
                Label(LocalizedStringKey(key), systemImage: "info.circle")
                    .font(.system(size: MacOSDrivingRouteDetailMetrics.noticeFontSize * scale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
