#if os(macOS)
import SwiftUI

/// 進行中セッションを終了済みアーカイブから分離して示すセクションです。
///
/// 見出しとカードは親のスタックへ直接並びます。進行中セッションがない時は何も描画しません。
struct MacOSConnectionHistoryActiveSection: View {
    /// 表示する未終了セッションです。
    let sessions: [ConnectionSession]
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 見出しと進行中セッションカードを並べます。
    ///
    /// 責務: 未終了セッション列を見出しとライブカードの並びへ変換します。
    var body: some View {
        if !sessions.isEmpty {
            MacOSConnectionHistorySectionTitle(
                titleKey: "history.active.title",
                systemImage: "dot.radiowaves.left.and.right",
                scale: scale
            )
            ForEach(sessions) { session in
                MacOSConnectionHistoryActiveSessionCard(session: session, scale: scale)
            }
        }
    }
}
#endif
