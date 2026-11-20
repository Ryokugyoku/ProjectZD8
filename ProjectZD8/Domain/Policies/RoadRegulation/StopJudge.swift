import Foundation

/// 一時停止の通過を、接近の前後の車速で判定します。取得間隔が粗く短い停止を見逃した可能性がある時は判定できないとします。
nonisolated struct StopJudge: Sendable {
    /// 判定に使うしきい値。
    private let thresholds: RoadRegulationMatchingThresholds

    /// しきい値を受け取って判定器を作ります。
    ///
    /// 責務: 判定に使うしきい値を保持します。
    /// - Parameter thresholds: 停止とみなす車速・証拠の窓の幅・前後のサンプルの上限・減速度などのしきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 一時停止の通過1回を判定します。
    ///
    /// 責務: 空白・条件・車速の有無を調べ、停止の証拠、取得間隔の順に判定を決めます。
    /// - Parameters:
    ///   - passage: 一時停止の通過。
    ///   - speeds: 走行全体の車速の時系列。
    /// - Returns: 判定結果。
    func judge(_ passage: StopPassage, speeds: VehicleSpeedTimeline) -> StopJudgement {
        StopJudgement(passage: passage, verdict: verdict(for: passage, speeds: speeds))
    }

    /// 通過1回の判定を決めます。
    ///
    /// 責務: §3.6 の一時停止の順序どおりに判定を選びます。
    /// - Parameters:
    ///   - passage: 一時停止の通過。
    ///   - speeds: 走行全体の車速の時系列。
    /// - Returns: 判定。
    private func verdict(for passage: StopPassage, speeds: VehicleSpeedTimeline) -> StopVerdict {
        if passage.interruptedByGap { return .undeterminable(.trackGap) }
        guard passage.applicability == .applies else { return .undeterminable(.conditionUnknown) }
        guard !speeds.isEmpty else { return .undeterminable(.speedUnavailable) }
        let start = Swift.min(passage.approachStarted.time, passage.reached.time)
        let reached = Swift.max(passage.approachStarted.time, passage.reached.time)
        guard start.isFinite, reached.isFinite else { return .undeterminable(.speedSamplingTooSparse) }
        if hasStopEvidence(start: start, reached: reached, speeds: speeds) { return .stopped }
        guard let bracket = bracketSamples(start: start, reached: reached, speeds: speeds),
              !mayHaveMissedStop(bracket),
              let minimumKph = bracket.map(\.kph).min() else {
            return .undeterminable(.speedSamplingTooSparse)
        }
        return .notStopped(minimumKph: minimumKph)
    }

    /// 接近の前後を少し広げた窓に、停止とみなせる車速があるかを返します。
    ///
    /// 責務: [開始 − 余裕, 到達 + 余裕] の中に停止の上限以下のサンプルがあるかを判定します。
    /// - Parameters:
    ///   - start: 接近を始めた時刻。
    ///   - reached: 到達した時刻。
    ///   - speeds: 車速の時系列。
    /// - Returns: 停止の証拠があれば `true`。
    private func hasStopEvidence(start: TimeInterval, reached: TimeInterval, speeds: VehicleSpeedTimeline) -> Bool {
        let margin = Swift.max(0, thresholds.stopEvidenceMarginSeconds)
        return speeds.samples(in: (start - margin)...(reached + margin))
            .contains { $0.kph <= thresholds.stoppedSpeedKph }
    }

    /// 接近の直前・接近中・到達の直後のサンプルを並べて返します。
    ///
    /// 責務: 開始以前で最後・区間内・到達以後で最初のサンプルを時刻の重複なしで集め、前後のサンプルが離れすぎていれば `nil` を返します。
    /// - Parameters:
    ///   - start: 接近を始めた時刻。
    ///   - reached: 到達した時刻。
    ///   - speeds: 車速の時系列。
    /// - Returns: 時刻の昇順のサンプル。前後のどちらかが無いか上限より離れていれば `nil`。
    private func bracketSamples(
        start: TimeInterval,
        reached: TimeInterval,
        speeds: VehicleSpeedTimeline
    ) -> [VehicleSpeedSample]? {
        let limit = thresholds.stopBracketMaximumSeconds
        guard let before = speeds.lastSample(atOrBefore: start), start - before.time <= limit,
              let after = speeds.firstSample(atOrAfter: reached), after.time - reached <= limit else {
            return nil
        }
        var samples = [before]
        for sample in speeds.samples(in: start...reached) + [after] where sample.time > (samples.last?.time ?? before.time) {
            samples.append(sample)
        }
        return samples
    }

    /// 隣どうしのサンプルの間に、停止して再び発進できるだけの時間があったかを返します。
    ///
    /// 責務: Δt ≥ (v1 + v2) / 3.6 / 最大減速度 となる組があるかを判定します。
    /// - Parameter samples: 時刻の昇順のサンプル。
    /// - Returns: 停止を見逃した可能性があれば `true`。
    private func mayHaveMissedStop(_ samples: [VehicleSpeedSample]) -> Bool {
        zip(samples, samples.dropFirst()).contains { earlier, later in
            let minimumSeconds = (earlier.kph + later.kph) / 3.6 / thresholds.maximumDecelerationMps2
            return later.time - earlier.time >= minimumSeconds
        }
    }
}
