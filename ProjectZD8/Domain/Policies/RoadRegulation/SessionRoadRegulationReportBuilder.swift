import Foundation

/// 規制の種類ごとの判定を集計し、1回の走行の判定結果にまとめます。文言は持たず、判定の case 名と件数だけを数えます。
nonisolated struct SessionRoadRegulationReportBuilder: Sendable {
    /// 判定1件を集計するための要約です。
    private struct TallyEntry {
        /// 判定の case 名。
        let caseName: String
        /// 判定できなかった時の理由。
        let reason: RoadRegulationUndeterminedReason?
    }

    /// 集計器を作ります。
    ///
    /// 責務: 状態を持たない集計器を用意します。
    init() {}

    /// 判定を集計して走行の判定結果を作ります。
    ///
    /// 責務: 4種類の判定を渡された順のまま保持し、種類ごとの集計と入力の範囲を添えます。
    /// - Parameters:
    ///   - speedLimit: 最高速度の判定。
    ///   - stops: 一時停止の判定。
    ///   - oneWay: 一方通行の判定。
    ///   - slowDown: 徐行の判定。
    ///   - coverage: 入力の範囲と質。
    /// - Returns: 走行の判定結果。
    func build(
        speedLimit: [SpeedLimitJudgement],
        stops: [StopJudgement],
        oneWay: [OneWayJudgement],
        slowDown: [SlowDownJudgement],
        coverage: RoadRegulationEvaluationCoverage
    ) -> SessionRoadRegulationReport {
        SessionRoadRegulationReport(
            speedLimit: speedLimit,
            stops: stops,
            oneWay: oneWay,
            slowDown: slowDown,
            speedLimitTally: Self.tally(speedLimit.map { Self.entry(for: $0.verdict) }),
            stopTally: Self.tally(stops.map { Self.entry(for: $0.verdict) }),
            oneWayTally: Self.tally(oneWay.map { Self.entry(for: $0.verdict) }),
            slowDownTally: Self.tally(slowDown.map { Self.entry(for: $0.verdict) }),
            coverage: coverage
        )
    }

    /// 要約の列を数えて集計にします。
    ///
    /// 責務: 総数、case 名ごとの件数、判定できなかった件数と理由ごとの件数を数えます(0件の名前・理由は含めない)。
    /// - Parameter entries: 判定の要約。
    /// - Returns: 集計。
    private static func tally(_ entries: [TallyEntry]) -> RoadRegulationKindTally {
        var verdictCounts: [String: Int] = [:]
        var byReason: [RoadRegulationUndeterminedReason: Int] = [:]
        for entry in entries {
            verdictCounts[entry.caseName, default: 0] += 1
            if let reason = entry.reason {
                byReason[reason, default: 0] += 1
            }
        }
        return RoadRegulationKindTally(
            total: entries.count,
            verdictCounts: verdictCounts,
            undetermined: byReason.values.reduce(0, +),
            undeterminedByReason: byReason
        )
    }

    /// 最高速度の判定を要約します。
    ///
    /// 責務: case 名と、判定できなかった時の理由を取り出します。
    /// - Parameter verdict: 判定。
    /// - Returns: 要約。
    private static func entry(for verdict: SpeedLimitVerdict) -> TallyEntry {
        switch verdict {
        case .withinLimit: TallyEntry(caseName: "withinLimit", reason: nil)
        case .exceeded: TallyEntry(caseName: "exceeded", reason: nil)
        case .unregulated: TallyEntry(caseName: "unregulated", reason: nil)
        case .undeterminable(let reason): TallyEntry(caseName: "undeterminable", reason: reason)
        }
    }

    /// 一時停止の判定を要約します。
    ///
    /// 責務: case 名と、判定できなかった時の理由を取り出します。
    /// - Parameter verdict: 判定。
    /// - Returns: 要約。
    private static func entry(for verdict: StopVerdict) -> TallyEntry {
        switch verdict {
        case .stopped: TallyEntry(caseName: "stopped", reason: nil)
        case .notStopped: TallyEntry(caseName: "notStopped", reason: nil)
        case .undeterminable(let reason): TallyEntry(caseName: "undeterminable", reason: reason)
        }
    }

    /// 一方通行の判定を要約します。
    ///
    /// 責務: case 名と、判定できなかった時の理由を取り出します。
    /// - Parameter verdict: 判定。
    /// - Returns: 要約。
    private static func entry(for verdict: OneWayVerdict) -> TallyEntry {
        switch verdict {
        case .followedDirection: TallyEntry(caseName: "followedDirection", reason: nil)
        case .possibleWrongWay: TallyEntry(caseName: "possibleWrongWay", reason: nil)
        case .undeterminable(let reason): TallyEntry(caseName: "undeterminable", reason: reason)
        }
    }

    /// 徐行の判定を要約します。
    ///
    /// 責務: case 名と、判定できなかった時の理由を取り出します。
    /// - Parameter verdict: 判定。
    /// - Returns: 要約。
    private static func entry(for verdict: SlowDownVerdict) -> TallyEntry {
        switch verdict {
        case .observed: TallyEntry(caseName: "observed", reason: nil)
        case .undeterminable(let reason): TallyEntry(caseName: "undeterminable", reason: reason)
        }
    }
}
