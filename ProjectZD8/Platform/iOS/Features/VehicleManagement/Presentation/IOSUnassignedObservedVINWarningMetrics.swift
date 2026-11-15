#if os(iOS)
import CoreGraphics

/// iOSの未登録車両の警告カードに使う表示寸法です。
enum IOSUnassignedObservedVINWarningMetrics {
    /// カード内の要素間隔です。
    static let spacing: CGFloat = 12
    /// カード内側の余白です。
    static let padding: CGFloat = 16
    /// カードの角丸半径です。
    static let cornerRadius: CGFloat = 20
    /// 画面端からの左右の余白です。
    static let horizontalInset: CGFloat = 20
    /// 画面上端からの余白です。
    static let topInset: CGFloat = 8
    /// 操作ボタンの最小の高さです。
    static let actionMinHeight: CGFloat = 44
}
#endif
