/// 応答駆動の取得ループで1件の要求が終わった結果です。
nonisolated struct LiveTelemetryRequestResult: Equatable, Sendable {
    /// 取得ループが所有する世代です。
    let generation: UInt
    /// 要求が属する周回のbatch番号です。
    let batchOrdinal: Int64
    /// 周回内で0から始まる要求順です。
    let requestOrdinal: Int
    /// 送ったService/PID要求です。
    let request: OBDPIDRequest
    /// Transport境界で直接確認した結果です。
    let outcome: OBDPIDRequestTransportOutcome
    /// 正応答payloadを取得時定義で評価した結果です。正応答以外では `.notEvaluated` です。
    let valueOutcome: PIDRequestValueOutcome
    /// 要求送信から結果受信までの単調経過時間です。
    let elapsedNanoseconds: UInt64

    /// 1件の要求結果を固定します。
    ///
    /// 責務: 周回内の位置、要求、Transport結果、値評価、経過時間を1件の記録入力へまとめます。
    /// - Parameters:
    ///   - generation: 取得ループが所有する世代。
    ///   - batchOrdinal: 要求が属する周回のbatch番号。
    ///   - requestOrdinal: 周回内で0から始まる要求順。
    ///   - request: 送ったService/PID要求。
    ///   - outcome: Transport境界で直接確認した結果。
    ///   - valueOutcome: 正応答payloadの値評価結果。正応答以外では `.notEvaluated`。
    ///   - elapsedNanoseconds: 要求送信から結果受信までの単調経過時間。
    init(
        generation: UInt,
        batchOrdinal: Int64,
        requestOrdinal: Int,
        request: OBDPIDRequest,
        outcome: OBDPIDRequestTransportOutcome,
        valueOutcome: PIDRequestValueOutcome,
        elapsedNanoseconds: UInt64
    ) {
        self.generation = generation
        self.batchOrdinal = batchOrdinal
        self.requestOrdinal = requestOrdinal
        self.request = request
        self.outcome = outcome
        self.valueOutcome = valueOutcome
        self.elapsedNanoseconds = elapsedNanoseconds
    }
}
