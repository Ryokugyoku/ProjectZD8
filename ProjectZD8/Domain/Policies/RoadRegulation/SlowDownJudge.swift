import Foundation

/// 徐行の区間の通過について、合否を付けずに区間内の最高車速を返します。
nonisolated struct SlowDownJudge: Sendable {
    /// 判定に使うしきい値。
    private let thresholds: RoadRegulationMatchingThresholds

    /// しきい値を受け取って判定器を作ります。
    ///
    /// 責務: 判定に使うしきい値を保持します。
    /// - Parameter thresholds: 徐行の参考の速さを含むしきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 徐行の区間1つを判定します。
    ///
    /// 責務: 区間の状態に応じて、区間内の最高車速か判定できない理由を返します。
    /// - Parameters:
    ///   - traversal: 徐行の経路の区間。
    ///   - speeds: 走行全体の車速の時系列。
    /// - Returns: 判定結果。
    func judge(_ traversal: RoadRegulationTraversal, speeds: VehicleSpeedTimeline) -> SlowDownJudgement {
        SlowDownJudgement(traversal: traversal, verdict: verdict(for: traversal, speeds: speeds))
    }

    /// 区間の状態から判定を選びます。
    ///
    /// 責務: 徐行の経路の状態ごとに判定を振り分けます。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - speeds: 車速の時系列。
    /// - Returns: 判定。
    private func verdict(for traversal: RoadRegulationTraversal, speeds: VehicleSpeedTimeline) -> SlowDownVerdict {
        guard case .slowDown(let status) = traversal.status else { return .undeterminable(.outsideRegulationData) }
        switch status {
        case .pending:
            return .undeterminable(.trackGap)
        case .none:
            return .undeterminable(.outsideRegulationData)
        case .undeterminable(let reason, _):
            return .undeterminable(reason)
        case .on:
            return observedVerdict(traversal, speeds: speeds)
        }
    }

    /// 徐行の区間の窓の中の最高車速を返します。
    ///
    /// 責務: 窓に車速があれば最高車速と参考の速さを返し、無ければ車速の有無で理由を分けます。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - speeds: 車速の時系列。
    /// - Returns: 判定。
    private func observedVerdict(_ traversal: RoadRegulationTraversal, speeds: VehicleSpeedTimeline) -> SlowDownVerdict {
        let start = traversal.start.time
        let end = traversal.end.time
        let window = start.isFinite && end.isFinite
            ? speeds.samples(in: Swift.min(start, end)...Swift.max(start, end))
            : []
        if let maxKph = window.map(\.kph).max() {
            return .observed(maxKph: maxKph, referenceKph: thresholds.slowDownReferenceKph)
        }
        return .undeterminable(speeds.isEmpty ? .speedUnavailable : .speedSamplingTooSparse)
    }
}
