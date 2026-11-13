import SwiftUI

/// 余白・間隔の基準値。すべての画面はこの値の組み合わせでレイアウトする。
enum InsightSpacing {
    /// 2pt。アイコンと文字の微調整など最小の隙間。
    static let xxs: CGFloat = 2
    /// 4pt。密接に関連する要素同士の隙間。
    static let xs: CGFloat = 4
    /// 8pt。同一グループ内の標準的な隙間。
    static let sm: CGFloat = 8
    /// 12pt。カード内部の要素間隔。
    static let md: CGFloat = 12
    /// 16pt。カード内余白・画面端の標準余白。
    static let lg: CGFloat = 16
    /// 24pt。セクション間の間隔。
    static let xl: CGFloat = 24
    /// 32pt。大きなブロック間の間隔。
    static let xxl: CGFloat = 32

    /// 画面左右の標準余白(iPhone SE 幅でも内容を圧迫しない値)。
    static let screenGutter: CGFloat = 16
    /// タップ可能な操作要素の最小高さ。
    static let minimumHitTarget: CGFloat = 44
}
