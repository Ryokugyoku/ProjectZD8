import Foundation

/// 一時停止の通過1回の判定結果です。
nonisolated struct StopJudgement: Equatable, Sendable {
    /// 判定した通過。
    let passage: StopPassage
    /// 判定。
    let verdict: StopVerdict
}
