import SwiftUI

/// 破壊的アクション(削除・サインアウト等)用ボタン(赤塗り)。
struct InsightDestructiveButtonStyle: ButtonStyle {
    /// スタイルを作る。
    ///
    /// 責務: 状態を持たないスタイルを生成する。
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        InsightButtonChrome(configuration: configuration, kind: .destructive)
    }
}

extension ButtonStyle where Self == InsightDestructiveButtonStyle {
    /// 破壊的アクション用スタイル。
    static var insightDestructive: InsightDestructiveButtonStyle { InsightDestructiveButtonStyle() }
}
