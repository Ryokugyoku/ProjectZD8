#if os(iOS)
import CoreGraphics

/// iOSホームに差し込むリアルタイム表示パネルの表示寸法です。
enum IOSLiveTelemetryPanelMetrics {
    /// パネル内の区画どうしの縦方向の間隔です。
    static let sectionSpacing: CGFloat = 18
    /// 区画の見出しと中身の間隔です。
    static let sectionContentSpacing: CGFloat = 12
    /// カードどうしの間隔です。
    static let cardSpacing: CGFloat = 12

    /// 状態バナーの左右の余白です。
    static let bannerHorizontalPadding: CGFloat = 16
    /// 状態バナーの最小の高さです。
    static let bannerMinHeight: CGFloat = 50
    /// 状態バナーの角丸半径です。
    static let bannerCornerRadius: CGFloat = 17
    /// 状態バナーの背景の不透明度です。
    static let bannerFillOpacity: Double = 0.09
    /// 状態バナーの枠線の不透明度です。
    static let bannerStrokeOpacity: Double = 0.18

    /// 主要値の数値の文字サイズです。
    static let primaryValueFontSize: CGFloat = 40
    /// 主要値の数値が収まらない時の最小縮小率です。
    static let primaryValueMinimumScale: CGFloat = 0.6
    /// 主要値カードの内側の余白です。
    static let primaryCardPadding: CGFloat = 17
    /// 主要値カードの最小の高さです。
    static let primaryCardMinHeight: CGFloat = 168
    /// 主要値カードの角丸半径です。
    static let primaryCardCornerRadius: CGFloat = 23
    /// 主要値カードのグラデーション始点の不透明度です。
    static let primaryCardTintOpacity: Double = 0.14
    /// 主要値カードの枠線の不透明度です。
    static let primaryCardStrokeOpacity: Double = 0.2

    /// 車種専用区画の内側の余白です。
    static let vehicleSectionPadding: CGFloat = 18
    /// 車種専用区画の角丸半径です。
    static let vehicleSectionCornerRadius: CGFloat = 24
    /// 車種専用区画の枠線の不透明度です。
    static let vehicleSectionStrokeOpacity: Double = 0.22
    /// 車種専用区画の小型カードの最小幅です。
    static let vehicleSectionCardMinWidth: CGFloat = 150

    /// 分類カードのアイコン枠の一辺です。
    static let categoryIconSize: CGFloat = 46
    /// 分類カードのアイコン枠の角丸半径です。
    static let categoryIconCornerRadius: CGFloat = 14
    /// 分類カードの内側の余白です。
    static let categoryCardPadding: CGFloat = 15
    /// 分類カードの角丸半径です。
    static let categoryCardCornerRadius: CGFloat = 20

    /// 小型カードの内側の余白です。
    static let compactCardPadding: CGFloat = 15
    /// 小型カードの最小の高さです。
    static let compactCardMinHeight: CGFloat = 96
    /// 小型カードの角丸半径です。
    static let compactCardCornerRadius: CGFloat = 18

    /// 分類詳細画面の内側の余白です。
    static let detailPadding: CGFloat = 18
    /// 分類詳細画面の背景の光の届く半径です。
    static let detailGlowRadius: CGFloat = 430
}
#endif
