/// 1周回の要求結果を集計し、周回後に取得を続けるかを判定します。
nonisolated struct LiveTelemetryRoundOutcome: Equatable, Sendable {
    /// 正応答を返した要求です。周回内の要求順に並びます。
    private(set) var respondedRequests: [OBDPIDRequest] = []
    /// 通信境界の喪失を観測したかどうかです。
    private(set) var observedTransportFailure = false
    /// 取消を観測したかどうかです。
    private(set) var observedCancellation = false

    /// 空の集計を生成します。
    ///
    /// 責務: 周回開始時の集計状態を構築します。
    init() {}

    /// 要求1件の結果を集計へ加えます。
    ///
    /// 責務: 正応答・通信失敗・取消の有無を周回単位で記録します。
    /// - Parameters:
    ///   - outcome: 要求1件のTransport観測。
    ///   - request: 結果が属するService/PID要求。
    mutating func add(_ outcome: OBDPIDRequestTransportOutcome, for request: OBDPIDRequest) {
        switch outcome {
        case .responded:
            respondedRequests.append(request)
        case .transportFailure:
            observedTransportFailure = true
        case .cancelled:
            observedCancellation = true
        case .unsupported, .timedOut, .unclassifiedResponse:
            break
        }
    }

    /// 周回後に取得を終えるべき理由を返します。
    ///
    /// 責務: 取消を停止、正応答の無い周回を通信断または無応答へ変換します。
    /// - Returns: 取得を終える理由。続ける場合は `nil`。
    var termination: LiveTelemetryAcquisitionTermination? {
        if observedCancellation { return .stopped }
        guard respondedRequests.isEmpty else { return nil }
        return observedTransportFailure ? .connectionLost : .noVehicleResponse
    }
}
