/// 記録中表示に載せる1項目の計測値です。値が無いことを `nil` ではなく明示ケースで表します。
nonisolated enum RecordingSessionActivityMetric: Equatable, Codable, Sendable {
    /// 取得済みの数値です(単位はPID定義の単位)。
    case value(Double)
    /// このセッションでまだ取得できていないか、車両が対応していません。
    case unavailable

    /// 「未取得」を表す文言のローカライズキーです。
    static let unavailableKey = "live_activity.metric.unavailable"

    /// 指定PIDの最新観測から計測値を生成します。
    ///
    /// 責務: 観測一覧から1つのService/PIDを引き、見つからなければ未取得へ変換します。
    /// - Parameters:
    ///   - request: 引くService/PID。
    ///   - samples: PIDごとの最新観測一覧。
    init(_ request: OBDPIDRequest, in samples: [OBDPIDSample]) {
        if let sample = samples.last(where: { $0.request == request }) {
            self = .value(sample.value)
        } else {
            self = .unavailable
        }
    }
}
