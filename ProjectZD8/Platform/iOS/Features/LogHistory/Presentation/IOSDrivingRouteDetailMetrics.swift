#if os(iOS)
import CoreGraphics

/// iPhone のセッション詳細の走行ルートのカードと、大きく表示した地図の寸法です。
enum IOSDrivingRouteDetailMetrics {
    /// カードの中の要素の縦の間隔です。
    static let cardSpacing: CGFloat = 12
    /// カードの内側の余白です。
    static let cardPadding: CGFloat = 16
    /// カードの角の半径です。
    static let cardCornerRadius: CGFloat = 22
    /// カードの中の地図の高さです。
    static let mapHeight: CGFloat = 220
    /// カードの中の地図の角の半径です。
    static let mapCornerRadius: CGFloat = 16
    /// 要約の項目どうしの横の間隔です。
    static let summarySpacing: CGFloat = 10
    /// 要約の1項目の中の、値と見出しの縦の間隔です。
    static let summaryItemSpacing: CGFloat = 4
    /// 注記どうしの縦の間隔です。
    static let noticeSpacing: CGFloat = 6
    /// 読み込み中・理由・失敗の表示の最小の高さです。
    static let statusMinHeight: CGFloat = 120
    /// 読み込み中・理由・失敗の表示の中の要素の縦の間隔です。
    static let statusSpacing: CGFloat = 10
    /// 理由・失敗のアイコンの大きさです。
    static let statusIconSize: CGFloat = 28
    /// 大きく表示した地図の上に重ねる要約の内側の余白です。
    static let sheetSummaryPadding: CGFloat = 14
    /// 大きく表示した地図の上に重ねる要約の角の半径です。
    static let sheetSummaryCornerRadius: CGFloat = 18
    /// 大きく表示した地図の上に重ねる要約と画面の端との間隔です。
    static let sheetSummaryInset: CGFloat = 16
}
#endif
