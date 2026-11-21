import Foundation

/// 規制の区間の通過が終わった理由です。
nonisolated enum RoadRegulationTraversalEndReason: String, Sendable {
    /// 状態が切り替わった。
    case changed
    /// 位置の記録が途切れた。
    case trackGap
    /// 軌跡が終わった。
    case trackEnded
}
