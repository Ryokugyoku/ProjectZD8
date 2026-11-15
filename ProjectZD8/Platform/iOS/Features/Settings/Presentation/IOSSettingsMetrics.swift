#if os(iOS)
import CoreGraphics

/// iOS設定画面のカードと選択行に使う表示寸法です。
enum IOSSettingsMetrics {
    /// カード内の見出しと操作領域の間隔です。
    static let cardSpacing: CGFloat = 17
    /// カード内側の余白です。
    static let cardPadding: CGFloat = 18
    /// カードの角丸半径です。
    static let cardCornerRadius: CGFloat = 24
    /// カード見出しのアイコン枠の一辺です。
    static let cardIconSize: CGFloat = 38
    /// カード見出しのアイコン枠の角丸半径です。
    static let cardIconCornerRadius: CGFloat = 12
    /// 選択行の最小の高さです。
    static let choiceRowMinHeight: CGFloat = 62
    /// 選択行の内側の余白です。
    static let choiceRowPadding: CGFloat = 12
    /// 選択行の角丸半径です。
    static let choiceRowCornerRadius: CGFloat = 16
    /// 選択行内の要素間隔です。
    static let choiceRowSpacing: CGFloat = 12
    /// 案内文の角丸半径です。
    static let noticeCornerRadius: CGFloat = 14
    /// 案内文の内側の余白です。
    static let noticePadding: CGFloat = 12
}
#endif
