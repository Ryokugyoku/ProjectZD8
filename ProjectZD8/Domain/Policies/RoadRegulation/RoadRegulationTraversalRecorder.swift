import Foundation

/// matcher の1歩ごとの変化から、区間の通過と一時停止の通過を組み立てます。
///
/// - 経路の状態が切り替わったら、それまでの区間を「切り替えの時刻(連続の最初の点)の直前の点」で `changed` として閉じ、
///   新しい区間を切り替えの時刻から始めます。
/// - `pending` と、一方通行・徐行の `none` は区間にしません。
/// - 空白(`trackGap`)では開いている区間を最後に使えた点で `trackGap` として閉じます。
/// - `finish()` で開いている区間を最後の点で `trackEnded` として閉じます。
/// 区間は閉じた順に返します(1つの経路の中では時刻の順)。
nonisolated struct RoadRegulationTraversalRecorder: Sendable {
    /// 経路の種類です。
    private enum Channel: CaseIterable {
        /// 最高速度。
        case speedLimit
        /// 一方通行。
        case oneWay
        /// 徐行。
        case slowDown
    }

    /// 開いている区間です。
    private struct OpenTraversal {
        /// 区間の状態。
        let status: RoadRegulationTraversalStatus
        /// 区間の最初の点。
        let start: RoadRegulationTransitionMark
    }

    /// 経路ごとの開いている区間です。
    private var open: [Channel: OpenTraversal] = [:]
    /// 記録した点の印(記録した順)。切り替えの時刻の直前の点を探すのに使います。
    private var marks: [RoadRegulationTransitionMark] = []
    /// 閉じた区間です。
    private var traversals: [RoadRegulationTraversal] = []
    /// 一時停止の通過です。
    private var stopPassages: [StopPassage] = []

    /// 空の記録器を作ります。
    ///
    /// 責務: 開いている区間も記録も無い状態から始めます。
    init() {}

    /// matcher の1歩を記録します。
    ///
    /// 責務: 1歩の変化を起きた順に取り込み、区間を閉じる・始める・一時停止の通過を足します。
    /// - Parameters:
    ///   - step: matcher の1歩の結果。
    ///   - point: その1歩に渡した点。
    mutating func record(_ step: RoadRegulationMatchStep, point: RoadRegulationTrackPoint) {
        let mark = RoadRegulationTransitionMark(time: point.time, sequence: point.sequence, observedAt: point.observedAt)
        guard step.state.lastUsableMark == mark else { return }
        marks.append(mark)
        for change in step.changes {
            apply(change)
        }
    }

    /// 記録を終え、区間と一時停止の通過を返します。
    ///
    /// 責務: 開いている区間を最後の点で `trackEnded` として閉じ、記録器を空に戻します。
    /// - Returns: 区間(閉じた順)と一時停止の通過(到達した順)。
    mutating func finish() -> (traversals: [RoadRegulationTraversal], stopPassages: [StopPassage]) {
        if let last = marks.last {
            closeAll(at: last, reason: .trackEnded)
        }
        let result = (traversals: traversals, stopPassages: stopPassages)
        self = RoadRegulationTraversalRecorder()
        return result
    }

    /// 1つの変化を取り込みます。
    ///
    /// 責務: 変化の種類ごとに、区間の切り替え・空白での終了・一時停止の通過の追加を振り分けます。
    /// - Parameter change: 変化。
    private mutating func apply(_ change: RoadRegulationChange) {
        switch change {
        case .speedLimitChanged(_, let to, let since):
            switchTraversal(.speedLimit, to: .speedLimit(to), isRecordable: to != .pending, since: since)
        case .oneWayChanged(_, let to, let since):
            switchTraversal(.oneWay, to: .oneWay(to), isRecordable: to != .pending && to != .none, since: since)
        case .slowDownChanged(_, let to, let since):
            switchTraversal(.slowDown, to: .slowDown(to), isRecordable: to != .pending && to != .none, since: since)
        case .trackGap(let lastUsable):
            closeAll(at: lastUsable, reason: .trackGap)
        case .stopReached(let passage):
            stopPassages.append(passage)
        case .stopApproachStarted, .stopApproachAbandoned:
            break
        }
    }

    /// 経路の区間を切り替えます。
    ///
    /// 責務: 開いている区間を切り替えの時刻の直前の点で閉じ、記録する状態なら新しい区間を始めます。
    /// - Parameters:
    ///   - channel: 経路。
    ///   - status: 新しい状態。
    ///   - isRecordable: 新しい状態を区間にするか。
    ///   - since: 切り替えの時刻(連続の最初の点)。
    private mutating func switchTraversal(
        _ channel: Channel,
        to status: RoadRegulationTraversalStatus,
        isRecordable: Bool,
        since: RoadRegulationTransitionMark
    ) {
        if let current = open[channel] {
            let end = mark(before: since, notBefore: current.start)
            traversals.append(RoadRegulationTraversal(status: current.status, start: current.start, end: end, endReason: .changed))
        }
        open[channel] = isRecordable ? OpenTraversal(status: status, start: since) : nil
    }

    /// 開いている区間をすべて閉じます。
    ///
    /// 責務: 経路の決まった順(最高速度・一方通行・徐行)に、指定した点と理由で閉じます。
    /// - Parameters:
    ///   - end: 区間の最後の点。
    ///   - reason: 終わった理由。
    private mutating func closeAll(at end: RoadRegulationTransitionMark, reason: RoadRegulationTraversalEndReason) {
        for channel in Channel.allCases {
            guard let current = open[channel] else { continue }
            traversals.append(RoadRegulationTraversal(status: current.status, start: current.start, end: end, endReason: reason))
        }
        open = [:]
    }

    /// 切り替えの時刻の直前に記録した点を返します。
    ///
    /// 責務: 記録した点を後ろから探し、切り替えの点の1つ前の点を返します。区間の最初の点より前にはしません。
    /// - Parameters:
    ///   - since: 切り替えの時刻(連続の最初の点)。
    ///   - start: 閉じる区間の最初の点。
    /// - Returns: 区間の最後の点。
    private func mark(
        before since: RoadRegulationTransitionMark,
        notBefore start: RoadRegulationTransitionMark
    ) -> RoadRegulationTransitionMark {
        guard let index = marks.lastIndex(of: since), index > 0 else { return start }
        let previous = marks[index - 1]
        return previous.time < start.time || previous.sequence < start.sequence ? start : previous
    }
}
