import Foundation

/// 観測した状態の揺らぎを抑え、同じ値が続いた時だけ状態を切り替えます(3つの経路で共有)。
nonisolated struct RoadRegulationStatusConfirmation<Status: Equatable & Sendable>: Equatable, Sendable {
    /// 確定している状態。
    private(set) var current: Status
    /// 切り替え待ちの状態。
    private var candidate: Status?
    /// 切り替え待ちの連続の最初の点。
    private var candidateSince: RoadRegulationTransitionMark?
    /// 切り替え待ちの状態が続いた点数。
    private var candidateCount = 0

    /// 確定している状態から始めます。
    ///
    /// 責務: 切り替え待ちの無い状態を作ります。
    /// - Parameter initial: 最初の確定状態。
    init(initial: Status) {
        self.current = initial
    }

    /// 1点で観測した状態を取り込みます。
    ///
    /// 責務: 確定状態と違う同じ値が `requiredCount` 点続いたら切り替え、連続の最初の点を切り替えの時刻にします。
    /// 確定状態と同じ値か、途中で違う値が来たら数え直します。
    /// - Parameters:
    ///   - status: この点で観測した状態。
    ///   - mark: この点の印。
    ///   - requiredCount: 切り替えに必要な連続の点数(1以下ならすぐ切り替える)。
    /// - Returns: 切り替えた時は前後の状態と切り替えの時刻。切り替えなければ `nil`。
    mutating func observe(
        _ status: Status,
        at mark: RoadRegulationTransitionMark,
        requiredCount: Int
    ) -> (from: Status, to: Status, since: RoadRegulationTransitionMark)? {
        guard status != current else {
            clearCandidate()
            return nil
        }
        let since = advanceCandidate(with: status, at: mark)
        guard candidateCount >= requiredCount else { return nil }
        let previous = current
        current = status
        clearCandidate()
        return (from: previous, to: status, since: since)
    }

    /// 確定状態を直接置き換えます。
    ///
    /// 責務: 空白の後などに、切り替え待ちを捨てて状態を戻します。
    /// - Parameter status: 新しい確定状態。
    mutating func reset(to status: Status) {
        current = status
        clearCandidate()
    }

    /// 切り替え待ちの連続を1点進めます。
    ///
    /// 責務: 同じ値なら数を増やし、違う値なら新しい連続をこの点から始めます。
    /// - Parameters:
    ///   - status: 観測した状態。
    ///   - mark: この点の印。
    /// - Returns: 連続の最初の点の印。
    private mutating func advanceCandidate(with status: Status, at mark: RoadRegulationTransitionMark) -> RoadRegulationTransitionMark {
        if candidate == status, let since = candidateSince {
            candidateCount += 1
            return since
        }
        candidate = status
        candidateSince = mark
        candidateCount = 1
        return mark
    }

    /// 切り替え待ちを捨てます。
    ///
    /// 責務: 連続の記録を空に戻します。
    private mutating func clearCandidate() {
        candidate = nil
        candidateSince = nil
        candidateCount = 0
    }
}
