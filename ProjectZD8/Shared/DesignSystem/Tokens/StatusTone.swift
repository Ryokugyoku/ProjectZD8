import SwiftUI

/// 状態バッジ・インジケーターの意味的なトーン。
enum StatusTone: Hashable, CaseIterable {
    /// 中立(情報なし・待機)。
    case neutral
    /// 進行中・アクティブ(アクセント色)。
    case active
    /// 正常・成功。
    case positive
    /// 注意(オレンジ)。
    case warning
    /// 異常・失敗。
    case critical

    /// トーンの代表色。
    var color: Color {
        switch self {
        case .neutral: InsightPalette.neutral
        case .active: InsightPalette.accent
        case .positive: InsightPalette.positive
        case .warning: InsightPalette.warning
        case .critical: InsightPalette.critical
        }
    }

    /// 色だけに依存しないための既定の SF Symbol 名。
    var defaultSymbol: String {
        switch self {
        case .neutral: "circle"
        case .active: "dot.radiowaves.left.and.right"
        case .positive: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}
