import SwiftUI

/// 空状態・バナー等に添える任意アクション(ローカライズ済みタイトル+ハンドラ)。
struct InsightAction {
    /// ボタンのタイトル。
    let title: Text
    /// タップ時の処理。
    let handler: () -> Void

    /// アクションを作る。
    ///
    /// 責務: タイトルとハンドラを束ねる。
    init(_ title: Text, handler: @escaping () -> Void) {
        self.title = title
        self.handler = handler
    }
}
