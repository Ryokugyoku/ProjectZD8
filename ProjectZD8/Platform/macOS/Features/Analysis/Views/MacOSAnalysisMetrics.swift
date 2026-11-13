#if os(macOS)
import CoreGraphics

/// macOSの分析画面の寸法です。
enum MacOSAnalysisMetrics {
    /// セッション一覧の幅(下限・理想・上限)です。
    static let listMinWidth: CGFloat = 220
    static let listIdealWidth: CGFloat = 260
    static let listMaxWidth: CGFloat = 340
    /// ワークベンチの最小幅です。
    static let webMinWidth: CGFloat = 480
    /// 一覧の行の縦余白です。
    static let rowVerticalPadding: CGFloat = 2
}
#endif
