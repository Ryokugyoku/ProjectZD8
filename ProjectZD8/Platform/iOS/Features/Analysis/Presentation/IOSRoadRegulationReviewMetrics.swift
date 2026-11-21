#if os(iOS)
import CoreGraphics

/// iPhone の解析画面の「交通規制との照合」のカード(状態・注記・まとめ・切替・一覧・出典)の寸法です。
enum IOSRoadRegulationReviewMetrics {
    /// カードの中の要素の縦の間隔です。
    static let sectionSpacing: CGFloat = 13
    /// まとめのタイルの列の数です。
    static let summaryColumns = 2
    /// まとめのタイルどうしの間隔と、タイルの中の要素の間隔です。
    static let summaryTileSpacing: CGFloat = 8
    /// まとめのタイルの内側の余白です。
    static let summaryTilePadding: CGFloat = 12
    /// まとめのタイルの角の半径です。
    static let summaryTileCornerRadius: CGFloat = 14
    /// 一覧の行どうしの間隔と、行の中の要素の間隔です。
    static let rowSpacing: CGFloat = 6
    /// 一覧の行の内側の余白です。
    static let rowPadding: CGFloat = 10
    /// 一覧の行の角の半径です。
    static let rowCornerRadius: CGFloat = 14
    /// 結果の色見本(丸)の大きさです。
    static let swatchSize: CGFloat = 10
    /// 状態の表示の最小の高さです。
    static let statusMinHeight: CGFloat = 120
    /// 出典と注意書きの行どうしの間隔です。
    static let attributionSpacing: CGFloat = 4
    /// 状態の表示の中の要素の縦の間隔です。
    static let statusSpacing: CGFloat = 10
    /// 状態の表示のアイコンの大きさです。
    static let statusIconSize: CGFloat = 28
    /// 注記どうしの縦の間隔です。
    static let noticeSpacing: CGFloat = 6
    /// 選ばれている行の枠の太さです。
    static let selectedBorderWidth: CGFloat = 2
    /// 選ばれていない行の枠の太さです。
    static let rowBorderWidth: CGFloat = 1
    /// 行とまとめのタイルの背景の不透明度です。
    static let tileBackgroundOpacity: Double = 0.04
    /// 選ばれていない行の枠の不透明度です。
    static let rowBorderOpacity: Double = 0.07
}
#endif
