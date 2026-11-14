/// 1周回の要求結果を集計します。
nonisolated struct LiveTelemetryRoundOutcome: Equatable, Sendable {
    /// 正応答を返した要求です。周回内の要求順に並びます。
    private(set) var respondedRequests: [OBDPIDRequest] = []

    /// 空の集計を生成します。
    ///
    /// 責務: 周回開始時の集計状態を構築します。
    init() {}

    /// 要求1件の結果を集計へ加えます。
    ///
    /// 責務: 正応答を返した要求を周回単位で記録します。
    /// - Parameters:
    ///   - outcome: 要求1件のTransport観測。
    ///   - request: 結果が属するService/PID要求。
    mutating func add(_ outcome: OBDPIDRequestTransportOutcome, for request: OBDPIDRequest) {
        if case .responded = outcome { respondedRequests.append(request) }
    }
}
