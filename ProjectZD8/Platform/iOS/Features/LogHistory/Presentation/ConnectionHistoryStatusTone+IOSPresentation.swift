#if os(iOS)
import SwiftUI

/// 共通の状態トーンへiOS接続履歴の表示色を付加します。
extension ConnectionHistoryStatusTone {
    /// iOS接続履歴の状態バッジに使う表示色です。
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .caution: .orange
        case .positive: .green
        case .critical: .red
        case .informative: .blue
        }
    }
}
#endif
