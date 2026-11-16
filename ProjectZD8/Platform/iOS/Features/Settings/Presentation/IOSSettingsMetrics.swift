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
    /// 案内文の背景の不透明度です。
    static let noticeFillOpacity: Double = 0.035
    /// 記録開始方法の選択行と案内文の間隔です。
    static let choiceRowListSpacing: CGFloat = 10
    /// 選択行のアイコンの大きさです。
    static let choiceRowIconFontSize: CGFloat = 16
    /// 選択中の選択行のアイコン背景の不透明度です。
    static let choiceRowSelectedIconFillOpacity: Double = 0.12
    /// 未選択の選択行のアイコン背景の不透明度です。
    static let choiceRowUnselectedIconFillOpacity: Double = 0.055
    /// 選択行の名称と説明の間隔です。
    static let choiceRowTextSpacing: CGFloat = 3
    /// 選択行の選択印の前に空ける最小の幅です。
    static let choiceRowSpacerMinLength: CGFloat = 4
    /// 選択中の選択行の背景の不透明度です。
    static let choiceRowSelectedFillOpacity: Double = 0.08
    /// 未選択の選択行の背景の不透明度です。
    static let choiceRowUnselectedFillOpacity: Double = 0.035

    /// 画面のカード同士の間隔です。
    static let screenSpacing: CGFloat = 16
    /// 画面の左右の余白です。
    static let screenHorizontalPadding: CGFloat = 20
    /// 画面の上の余白です。
    static let screenTopPadding: CGFloat = 18
    /// 画面の下の余白です。
    static let screenBottomPadding: CGFloat = 28
    /// 注目要求でアダプター設定カードへスクロールするアニメーションの時間(秒)です。
    static let attentionScrollDuration: Double = 0.26
    /// アダプター設定カードを振動させるアニメーションの時間(秒)です。
    static let attentionShakeDuration: Double = 0.56
    /// アダプター設定カードの振動の振れ幅です。
    static let attentionShakeAmplitude: CGFloat = 8

    /// 見出しのアイコンと文言の間隔です。
    static let headerSpacing: CGFloat = 15
    /// 見出しのアイコン枠の一辺です。
    static let headerIconSize: CGFloat = 58
    /// 見出しのアイコン枠の角丸半径です。
    static let headerIconCornerRadius: CGFloat = 18
    /// 見出しのアイコンの大きさです。
    static let headerIconFontSize: CGFloat = 23
    /// 見出しのアイコン枠の背景の不透明度です。
    static let headerIconFillOpacity: Double = 0.14
    /// 見出しのアイコン枠の線の不透明度です。
    static let headerIconStrokeOpacity: Double = 0.2
    /// 見出しのタイトルと副題の間隔です。
    static let headerTextSpacing: CGFloat = 4
    /// 見出しの下の余白です。
    static let headerBottomPadding: CGFloat = 8

    /// 外観モードのボタン同士の間隔です。
    static let appearanceButtonSpacing: CGFloat = 8
    /// 外観モードのボタン内のアイコンと文言の間隔です。
    static let appearanceButtonContentSpacing: CGFloat = 7
    /// 外観モードのボタンのアイコンの大きさです。
    static let appearanceIconFontSize: CGFloat = 17
    /// 外観モードのボタンの文言の大きさです。
    static let appearanceTitleFontSize: CGFloat = 10
    /// 外観モードのボタンの文言の最小縮小率です。
    static let appearanceTitleMinimumScaleFactor: CGFloat = 0.72
    /// 外観モードのボタンの最小の高さです。
    static let appearanceButtonMinHeight: CGFloat = 64
    /// 外観モードのボタンの角丸半径です。
    static let appearanceButtonCornerRadius: CGFloat = 15
    /// 未選択の外観モードのボタンの文言・アイコンの不透明度です。
    static let appearanceUnselectedForegroundOpacity: Double = 0.72
    /// 未選択の外観モードのボタンの背景の不透明度です。
    static let appearanceUnselectedFillOpacity: Double = 0.04
    /// 選択中の外観モードのボタンの線の不透明度です。
    static let appearanceSelectedStrokeOpacity: Double = 0.2
    /// 未選択の外観モードのボタンの線の不透明度です。
    static let appearanceUnselectedStrokeOpacity: Double = 0.06

    /// アダプター行同士の間隔です。
    static let adapterRowListSpacing: CGFloat = 10
    /// アダプター行のアイコンの大きさです。
    static let adapterRowIconFontSize: CGFloat = 16
    /// プライマリーのアダプター行のアイコン背景の不透明度です。
    static let adapterRowPrimaryIconFillOpacity: Double = 0.12
    /// セカンダリーのアダプター行のアイコン背景・役割バッジ背景の不透明度です。
    static let adapterRowSecondaryFillOpacity: Double = 0.055
    /// アダプター行の名称と説明の間隔です。
    static let adapterRowTextSpacing: CGFloat = 3
    /// アダプター行の名称と役割バッジの間隔です。
    static let adapterRowTitleSpacing: CGFloat = 6
    /// 役割バッジの文言の大きさです。
    static let adapterBadgeFontSize: CGFloat = 8
    /// 役割バッジの左右の余白です。
    static let adapterBadgeHorizontalPadding: CGFloat = 6
    /// 役割バッジの上下の余白です。
    static let adapterBadgeVerticalPadding: CGFloat = 3
    /// アダプター行の右端の矢印の前に空ける最小の幅です。
    static let adapterRowSpacerMinLength: CGFloat = 4
    /// アダプター行の背景の不透明度です。
    static let adapterRowFillOpacity: Double = 0.035

    /// 自動アップロードの切り替えの最小の高さです。
    static let uploadToggleMinHeight: CGFloat = 48
    /// 自動アップロードの切り替えの左右の余白です。
    static let uploadToggleHorizontalPadding: CGFloat = 14
    /// 自動アップロードの切り替えの背景の不透明度です。
    static let uploadToggleFillOpacity: Double = 0.045
    /// 自動アップロードの切り替えの角丸半径です。
    static let uploadToggleCornerRadius: CGFloat = 14

    /// アカウント削除カード内の間隔です。
    static let accountDeletionSpacing: CGFloat = 14
    /// アカウント削除の開始ボタンの最小の高さです。
    static let accountDeletionButtonMinHeight: CGFloat = 44
    /// アカウント削除カードの背景の不透明度です。
    static let accountDeletionFillOpacity: Double = 0.055
    /// アカウント削除カードの線の不透明度です。
    static let accountDeletionStrokeOpacity: Double = 0.22
}
#endif
