#if os(iOS)
import CoreGraphics

/// iOSの分析画面の寸法です。
enum IOSAnalysisMetrics {
    /// 全画面カバーの閉じる操作(右上)のためにワークベンチ上部バーの右端へ空ける幅(CSSピクセル)です。
    static let closeControlInset = 56
    /// セッション選択シートの行の縦余白です。
    static let rowVerticalPadding: CGFloat = 4
}
#endif
