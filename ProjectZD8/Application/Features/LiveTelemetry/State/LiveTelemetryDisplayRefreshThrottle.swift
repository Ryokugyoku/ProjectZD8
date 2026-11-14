/// 受信した観測を保持し、前回の表示更新から最小間隔が経った時だけまとめて表示へ渡します。
///
/// 間引いた観測は捨てずに保持し、次の更新でまとめて返します。フェーズ変化の時は `takeAll` で間隔を待たずに返します。
nonisolated struct LiveTelemetryDisplayRefreshThrottle: Equatable, Sendable {
    /// 表示更新の最小間隔(ナノ秒)です。
    static let minimumIntervalNanoseconds: UInt64 = 250_000_000

    /// 表示へまだ渡していない観測です。受信順に並びます。
    private(set) var pendingSamples: [OBDPIDSample] = []
    /// 前回の表示更新の単調時計の値です。まだ更新していない場合は `nil` です。
    private(set) var lastRefreshNanoseconds: UInt64?

    /// 保持中の観測が無い状態を生成します。
    ///
    /// 責務: 取得開始時の空の間引き状態を構築します。
    init() {}

    /// 受信した観測を保持します。
    ///
    /// 責務: 1件の観測を次の表示更新まで保持します。
    /// - Parameter sample: 受信した観測。
    mutating func hold(_ sample: OBDPIDSample) {
        pendingSamples.append(sample)
    }

    /// 最小間隔が経っていれば保持中の観測をまとめて返します。
    ///
    /// 責務: 前回の表示更新からの経過で更新可否を判定し、更新する場合は保持中の観測を払い出します。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 表示へ反映する観測。更新しない場合と保持中の観測が無い場合は `nil`。
    mutating func takeIfDue(nowNanoseconds: UInt64) -> [OBDPIDSample]? {
        guard !pendingSamples.isEmpty else { return nil }
        if let lastRefreshNanoseconds,
           nowNanoseconds < lastRefreshNanoseconds
            || nowNanoseconds - lastRefreshNanoseconds < Self.minimumIntervalNanoseconds {
            return nil
        }
        return takeAll(nowNanoseconds: nowNanoseconds)
    }

    /// 間隔にかかわらず保持中の観測をすべて返します。
    ///
    /// 責務: フェーズ変化の表示更新のために保持中の観測を払い出し、更新時刻を記録します。
    /// - Parameter nowNanoseconds: 単調時計の現在値。
    /// - Returns: 受信順の保持中の観測。無い場合は空配列。
    mutating func takeAll(nowNanoseconds: UInt64) -> [OBDPIDSample] {
        let samples = pendingSamples
        pendingSamples = []
        lastRefreshNanoseconds = nowNanoseconds
        return samples
    }
}
