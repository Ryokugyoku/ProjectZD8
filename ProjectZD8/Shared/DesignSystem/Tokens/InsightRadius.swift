import SwiftUI

/// 角丸半径の基準値。入れ子の要素は外側より小さい半径を使う。
enum InsightRadius {
    /// 6pt。バッジ・小さなチップ。
    static let xs: CGFloat = 6
    /// 10pt。バナー内部やボタン。
    static let sm: CGFloat = 10
    /// 14pt。カード。
    static let md: CGFloat = 14
    /// 20pt。大きなカード・オーバーレイ。
    static let lg: CGFloat = 20
    /// 28pt。フローティングのガラス要素。
    static let xl: CGFloat = 28
}
