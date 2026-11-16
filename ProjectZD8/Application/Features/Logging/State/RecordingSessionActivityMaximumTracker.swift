/// 観測のたびに、車速・回転数・スロットル開度の最大値を更新する集計器です。
///
/// 表示更新の間引きとは独立に、受け取った観測をすべて集計します。有限でない値は欠損として無視します。
nonisolated struct RecordingSessionActivityMaximumTracker: Equatable, Sendable {
    /// ここまでの最大値です。観測が無い項目は未取得です。
    private(set) var maximums = RecordingSessionActivityMaximums()

    /// 集計器を生成します。
    ///
    /// 責務: 全項目が未取得の集計器を作ります。
    init() {}

    /// 観測一覧を取り込み、最大値を更新します。
    ///
    /// 責務: 項目ごとに対応するPIDの有限な値だけを見て、最大値を下げずに更新します。
    /// - Parameter samples: PIDごとの最新観測一覧。
    mutating func record(_ samples: [OBDPIDSample]) {
        maximums.vehicleSpeed = Self.raised(maximums.vehicleSpeed, request: RecordingSessionActivityContent.vehicleSpeedRequest, in: samples)
        maximums.engineSpeed = Self.raised(maximums.engineSpeed, request: RecordingSessionActivityContent.engineSpeedRequest, in: samples)
        maximums.throttlePosition = Self.raised(
            maximums.throttlePosition, request: RecordingSessionActivityContent.throttlePositionRequest, in: samples
        )
    }

    /// 最大値をすべて未取得へ戻します。
    ///
    /// 責務: 新しいセッションの開始時に、前のセッションの最大値を引き継がないようにします。
    mutating func reset() {
        maximums = RecordingSessionActivityMaximums()
    }

    /// 現在の最大値を、観測一覧の値で引き上げます。
    ///
    /// 責務: 指定PIDの有限な値の最大が現在値を上回る時だけ置き換えます。
    /// - Parameters:
    ///   - current: 現在の最大値。
    ///   - request: 対象のService/PID。
    ///   - samples: 観測一覧。
    /// - Returns: 更新後の最大値。
    private static func raised(
        _ current: RecordingSessionActivityMetric,
        request: OBDPIDRequest,
        in samples: [OBDPIDSample]
    ) -> RecordingSessionActivityMetric {
        let best = samples.filter { $0.request == request && $0.value.isFinite }.map(\.value).max()
        guard let best else { return current }
        if case let .value(existing) = current, existing >= best { return current }
        return .value(best)
    }
}
