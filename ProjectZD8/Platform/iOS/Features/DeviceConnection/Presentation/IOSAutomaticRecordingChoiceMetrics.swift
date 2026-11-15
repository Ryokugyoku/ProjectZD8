#if os(iOS)
import CoreGraphics

/// iOSの記録開始方法の選択画面に使う表示寸法です。
enum IOSAutomaticRecordingChoiceMetrics {
    /// 画面要素の縦方向の間隔です。
    static let sectionSpacing: CGFloat = 24
    /// 選択肢どうしの間隔です。
    static let optionSpacing: CGFloat = 12
    /// 画面左右の余白です。
    static let horizontalPadding: CGFloat = 20
    /// 画面上端の余白です。
    static let topPadding: CGFloat = 32
    /// 画面下端の余白です。
    static let bottomPadding: CGFloat = 28
    /// 見出しアイコン枠の一辺です。
    static let heroIconSize: CGFloat = 72
    /// 見出しアイコン枠の角丸半径です。
    static let heroIconCornerRadius: CGFloat = 22
    /// 選択肢ボタンの内側の余白です。
    static let optionPadding: CGFloat = 16
    /// 選択肢ボタンの角丸半径です。
    static let optionCornerRadius: CGFloat = 20
    /// 選択肢ボタン内のアイコン枠の一辺です。
    static let optionIconSize: CGFloat = 44
    /// 選択肢ボタンの最小の高さです。
    static let optionMinHeight: CGFloat = 76
}
#endif
