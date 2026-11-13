import Foundation

/// 1件のPID要求とその結果です。Rawログの最小単位で、追記のみ行います。
nonisolated struct SessionSample: Equatable, Codable, Sendable {
    /// セッション内の通し番号です(0始まり、欠番なし)。
    let sequence: Int64
    /// この要求を発行したポーリングティックの番号です。
    let tick: Int
    /// セッション開始からの経過時間(マイクロ秒、単調増加時計)です。応答を受信した時点、または無応答が確定した時点で採取します。
    let elapsedMicroseconds: Int64
    let request: OBDPIDRequest
    let outcome: SampleOutcome
    /// サービス・PIDのエコーを除いた応答データです。応答が無い場合は空です。
    let payload: Data

    /// サンプルを生成します。
    ///
    /// 責務: 1件の要求結果を追記可能なRaw行としてまとめます。
    init(sequence: Int64, tick: Int, elapsedMicroseconds: Int64, request: OBDPIDRequest, outcome: SampleOutcome, payload: Data = Data()) {
        self.sequence = sequence
        self.tick = tick
        self.elapsedMicroseconds = elapsedMicroseconds
        self.request = request
        self.outcome = outcome
        self.payload = payload
    }
}
