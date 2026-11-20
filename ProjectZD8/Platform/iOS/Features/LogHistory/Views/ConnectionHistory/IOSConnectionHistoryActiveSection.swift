#if os(iOS)
import SwiftUI

/// 進行中セッションを終了済みアーカイブから分離して示すセクションです。
///
/// 見出しとカードは親のスタックへ直接並びます。進行中セッションがない時は何も描画しません。
struct IOSConnectionHistoryActiveSection: View {
    /// 表示する未終了セッションです。
    let sessions: [ConnectionSession]

    /// 見出しと進行中セッションカードを並べます。
    ///
    /// 責務: 未終了セッション列を見出しとライブカードの並びへ配置します。
    var body: some View {
        if !sessions.isEmpty {
            IOSConnectionHistorySectionTitle(titleKey: "history.active.title", systemImage: "dot.radiowaves.left.and.right")
            ForEach(sessions) { session in IOSConnectionHistoryActiveSessionCard(session: session) }
        }
    }
}
#endif
