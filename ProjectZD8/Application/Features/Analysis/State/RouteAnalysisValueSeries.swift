/// 1つの PID の値を時刻順に並べた列です。
nonisolated struct RouteAnalysisValueSeries: Equatable, Sendable {
    /// 値を記録した PID です。
    let pid: OBDPIDRequest
    /// 値の単位です。PID 定義に無い時は `nil` です。
    let unit: String?
    /// `date` の昇順に並んだ値です。
    let samples: [RouteAnalysisValueSample]

    /// 値が1件も無い時に `true` です。
    var isEmpty: Bool {
        samples.isEmpty
    }
}
