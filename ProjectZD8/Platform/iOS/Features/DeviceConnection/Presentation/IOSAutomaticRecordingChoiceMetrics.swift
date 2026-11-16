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
    /// 見出しのアイコン・タイトル・説明の間隔です。
    static let headingSpacing: CGFloat = 14
    /// 見出しアイコンの大きさです。
    static let heroIconFontSize: CGFloat = 30
    /// 見出しアイコン枠の背景の不透明度です。
    static let heroIconFillOpacity: Double = 0.13
    /// 選択肢ボタン内のアイコンと文言の間隔です。
    static let optionContentSpacing: CGFloat = 14
    /// 選択肢ボタンのアイコンの大きさです。
    static let optionIconFontSize: CGFloat = 19
    /// 選択肢ボタンのアイコン枠の背景の不透明度です。
    static let optionIconFillOpacity: Double = 0.12
    /// 選択肢ボタンの名称と説明の間隔です。
    static let optionTextSpacing: CGFloat = 4
    /// 選択肢ボタンの矢印の前に空ける最小の幅です。
    static let optionSpacerMinLength: CGFloat = 4
    /// 選択肢ボタンの枠線の不透明度です。
    static let optionStrokeOpacity: Double = 0.18
}
#endif
