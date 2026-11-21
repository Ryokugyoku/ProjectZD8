import Foundation

/// 最高速度の区間の通過を、区間の窓の中の車速と制限速度 + 許容幅で判定します。
nonisolated struct SpeedLimitJudge: Sendable {
    /// 超過の連続1つの要約です。
    private struct ExceedRun {
        /// 連続の中の最高車速(km/h)。
        let maxKph: Double
        /// 連続の最初から最後までの秒数。
        let durationSeconds: Double
    }

    /// 判定に使うしきい値。
    private let thresholds: RoadRegulationMatchingThresholds

    /// しきい値を受け取って判定器を作ります。
    ///
    /// 責務: 判定に使うしきい値を保持します。
    /// - Parameter thresholds: 許容幅・超過の連続・取得間隔などのしきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 最高速度の区間1つを判定します。
    ///
    /// 責務: 区間の状態に応じて、制限内・超過・指定なし・判定できないのいずれかを返します。
    /// - Parameters:
    ///   - traversal: 最高速度の経路の区間。
    ///   - speeds: 走行全体の車速の時系列。
    /// - Returns: 判定結果。規制に乗っていない区間の `limitKph` は `nil`。
    func judge(_ traversal: RoadRegulationTraversal, speeds: VehicleSpeedTimeline) -> SpeedLimitJudgement {
        guard case .speedLimit(let status) = traversal.status else {
            return SpeedLimitJudgement(traversal: traversal, limitKph: nil, verdict: .undeterminable(.outsideRegulationData))
        }
        switch status {
        case .pending:
            return SpeedLimitJudgement(traversal: traversal, limitKph: nil, verdict: .undeterminable(.trackGap))
        case .unregulated:
            return SpeedLimitJudgement(traversal: traversal, limitKph: nil, verdict: .unregulated)
        case .undeterminable(let reason, _):
            return SpeedLimitJudgement(traversal: traversal, limitKph: nil, verdict: .undeterminable(reason))
        case .regulated(_, let limitKph):
            let verdict = regulatedVerdict(traversal, limitKph: limitKph, speeds: speeds)
            return SpeedLimitJudgement(traversal: traversal, limitKph: limitKph, verdict: verdict)
        }
    }

    /// 制限速度のある区間を判定します。
    ///
    /// 責務: 車速の有無、超過の連続、取得間隔の順に調べて判定を決めます。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - limitKph: 制限速度(km/h)。
    ///   - speeds: 走行全体の車速の時系列。
    /// - Returns: 判定。
    private func regulatedVerdict(
        _ traversal: RoadRegulationTraversal,
        limitKph: Int,
        speeds: VehicleSpeedTimeline
    ) -> SpeedLimitVerdict {
        guard !speeds.isEmpty else { return .undeterminable(.speedUnavailable) }
        let window = Self.window(of: traversal, in: speeds)
        let threshold = Double(limitKph) + thresholds.speedTolerance(limitKph: limitKph)
        let runs = exceedRuns(in: window, aboveKph: threshold)
        if !runs.isEmpty {
            return exceededVerdict(runs, limitKph: limitKph)
        }
        guard isDenselySampled(window, traversal: traversal), let maxKph = window.map(\.kph).max() else {
            return .undeterminable(.speedSamplingTooSparse)
        }
        return .withinLimit(maxKph: maxKph)
    }

    /// 超過の連続から判定を作ります。
    ///
    /// 責務: 最大の超過量が別の道路の疑いの基準以上なら判定できないとし、そうでなければ超過とします。
    /// - Parameters:
    ///   - runs: 長さの条件を満たした超過の連続(1つ以上)。
    ///   - limitKph: 制限速度(km/h)。
    /// - Returns: 判定。
    private func exceededVerdict(_ runs: [ExceedRun], limitKph: Int) -> SpeedLimitVerdict {
        let maxKph = runs.map(\.maxKph).max() ?? Double(limitKph)
        if maxKph - Double(limitKph) >= thresholds.implausibleExcessKph {
            return .undeterminable(.possiblyDifferentRoad)
        }
        let seconds = runs.reduce(0.0) { $0 + $1.durationSeconds }
        return .exceeded(maxKph: maxKph, exceededSeconds: seconds)
    }

    /// 窓の中から超過の連続を探します。
    ///
    /// 責務: 基準を超えるサンプルが間隔の上限以内で続く区切りを作り、最短の長さを満たすものだけを返します。
    /// - Parameters:
    ///   - window: 区間の窓の中のサンプル(時刻の昇順)。
    ///   - threshold: これを超えたら超過とする車速(km/h)。
    /// - Returns: 超過の連続(時刻の順)。
    private func exceedRuns(in window: ArraySlice<VehicleSpeedSample>, aboveKph threshold: Double) -> [ExceedRun] {
        var runs: [ExceedRun] = []
        var current: [VehicleSpeedSample] = []
        for sample in window {
            let continuesRun = current.last.map { sample.time - $0.time <= thresholds.maximumExceedRunGapSeconds } ?? true
            if sample.kph <= threshold || !continuesRun {
                appendRun(current, to: &runs)
                current = []
            }
            if sample.kph > threshold {
                current.append(sample)
            }
        }
        appendRun(current, to: &runs)
        return runs
    }

    /// 超過の連続の候補が最短の長さを満たせば加えます。
    ///
    /// 責務: 最初から最後までの秒数を求め、最短の長さ以上なら要約して加えます。
    /// - Parameters:
    ///   - samples: 連続した超過のサンプル。
    ///   - runs: 加える先。
    private func appendRun(_ samples: [VehicleSpeedSample], to runs: inout [ExceedRun]) {
        guard let first = samples.first, let last = samples.last else { return }
        let duration = last.time - first.time
        guard duration >= thresholds.minimumExceedDurationSeconds else { return }
        runs.append(ExceedRun(maxKph: samples.map(\.kph).max() ?? last.kph, durationSeconds: duration))
    }

    /// 制限内と言い切れるだけ車速が取れているかを返します。
    ///
    /// 責務: 窓が空でなく、始まり側・終わり側の空きと隣どうしの間隔がすべて上限以内かを判定します。
    /// - Parameters:
    ///   - window: 区間の窓の中のサンプル。
    ///   - traversal: 区間。
    /// - Returns: 取得間隔が十分なら `true`。
    private func isDenselySampled(_ window: ArraySlice<VehicleSpeedSample>, traversal: RoadRegulationTraversal) -> Bool {
        guard let first = window.first, let last = window.last else { return false }
        let maximumGap = thresholds.maximumSpeedSampleGapSeconds
        let lower = Swift.min(traversal.start.time, traversal.end.time)
        let upper = Swift.max(traversal.start.time, traversal.end.time)
        guard first.time - lower <= maximumGap, upper - last.time <= maximumGap else { return false }
        return zip(window, window.dropFirst()).allSatisfy { $1.time - $0.time <= maximumGap }
    }

    /// 区間の窓 [開始, 終了] の中の車速を返します。
    ///
    /// 責務: 開始と終了の時刻から窓を作り、時系列から切り出します。時刻が有限でなければ空を返します。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - speeds: 車速の時系列。
    /// - Returns: 窓の中のサンプル。
    private static func window(
        of traversal: RoadRegulationTraversal,
        in speeds: VehicleSpeedTimeline
    ) -> ArraySlice<VehicleSpeedSample> {
        let start = traversal.start.time
        let end = traversal.end.time
        guard start.isFinite, end.isFinite else { return [] }
        return speeds.samples(in: Swift.min(start, end)...Swift.max(start, end))
    }
}
