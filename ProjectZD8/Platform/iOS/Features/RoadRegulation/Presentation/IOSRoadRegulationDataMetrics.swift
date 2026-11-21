#if os(iOS)
import CoreGraphics

/// iOSの交通規制データの管理画面に使う表示寸法です。
enum IOSRoadRegulationDataMetrics {
    /// 都道府県の行の中の要素の間隔です。
    static let rowSpacing: CGFloat = 8
    /// 都道府県の行の上下の余白です。
    static let rowVerticalPadding: CGFloat = 4
    /// 都道府県名と状態の間隔です。
    static let rowTitleSpacing: CGFloat = 8
    /// 版の詳細の行同士の間隔です。
    static let detailSpacing: CGFloat = 2
    /// 行のボタン同士の間隔です。
    static let buttonSpacing: CGFloat = 10
    /// 状態のバッジの左右の余白です。
    static let badgeHorizontalPadding: CGFloat = 8
    /// 状態のバッジの上下の余白です。
    static let badgeVerticalPadding: CGFloat = 3
    /// 状態のバッジの背景の不透明度です。
    static let badgeFillOpacity: Double = 0.12
    /// 進み具合の表示の要素の間隔です。
    static let progressSpacing: CGFloat = 4
    /// 「更新を確認」の欄の要素の間隔です。
    static let catalogHeaderSpacing: CGFloat = 8
    /// 出典の欄の要素の間隔です。
    static let attributionSpacing: CGFloat = 8
}
#endif
