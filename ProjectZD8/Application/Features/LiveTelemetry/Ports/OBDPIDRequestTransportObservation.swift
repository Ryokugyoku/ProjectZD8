/// 1件のPID要求についてTransport境界で直接確認できた結果です。
nonisolated enum OBDPIDRequestTransportOutcome: Equatable, Sendable {
    /// 要求と一致する正応答payloadを受信しました。
    case responded([UInt8])
    /// protocol上の明示証拠により要求PID非対応を確認しました。
    case unsupported
    /// 要求送信後に応答期限が切れました。
    case timedOut
    /// 要求送信後に呼出元の取消を確認しました。
    case cancelled
    /// 要求送信後にTransport接続を失いました。
    case transportFailure
    /// 応答文字列は得ましたが非対応または形式不正を安全に分類できません。
    case unclassifiedResponse
}

/// 1件のPID要求とTransport観測結果を対応付けます。
nonisolated struct OBDPIDRequestTransportObservation: Equatable, Sendable {
    /// 観測対象のService/PID要求です。
    let request: OBDPIDRequest
    /// Transport境界で直接確認した結果です。
    let outcome: OBDPIDRequestTransportOutcome

    /// PID要求と確認済みTransport結果を固定します。
    ///
    /// 責務: 1件の要求を推測を含まないTransport観測結果へ対応付けます。
    /// - Parameters:
    ///   - request: 観測対象のService/PID要求。
    ///   - outcome: Transport境界で直接確認した結果。
    init(request: OBDPIDRequest, outcome: OBDPIDRequestTransportOutcome) {
        self.request = request
        self.outcome = outcome
    }
}
