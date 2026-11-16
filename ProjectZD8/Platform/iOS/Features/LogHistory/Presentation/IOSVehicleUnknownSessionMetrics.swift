#if os(iOS)
import CoreGraphics

/// iOSの車両不明ログの警告と紐付け画面の寸法です。
enum IOSVehicleUnknownSessionMetrics {
    /// 警告の要素間の間隔です。
    static let spacing: CGFloat = 12
    /// 警告の内側の余白です。
    static let padding: CGFloat = 16
    /// 警告の角の半径です。
    static let cornerRadius: CGFloat = 20
    /// 警告の左右の外側の余白です。
    static let horizontalInset: CGFloat = 20
    /// 警告の上の外側の余白です。
    static let topInset: CGFloat = 8
    /// 主要操作のボタンの最小の高さです。
    static let actionMinHeight: CGFloat = 44
    /// 紐付け画面の行の要素間の間隔です。
    static let rowSpacing: CGFloat = 4
}
#endif
