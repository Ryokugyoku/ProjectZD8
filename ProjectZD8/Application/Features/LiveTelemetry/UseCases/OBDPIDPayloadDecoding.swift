/// 1件の正応答payloadを取得時定義で評価した結果です。
nonisolated struct OBDPIDPayloadDecoding: Equatable, Sendable {
    /// 取得証跡へ残す値の評価結果です。
    let valueOutcome: PIDRequestValueOutcome
    /// 表示へ流す数値観測です。数値化できない場合は `nil` です。
    let sample: OBDPIDSample?

    /// 値の評価結果と表示用観測を対応付けます。
    ///
    /// 責務: 同じpayloadから得た証跡用の分類と表示用の観測を1件にまとめます。
    /// - Parameters:
    ///   - valueOutcome: 取得証跡へ残す値の評価結果。
    ///   - sample: 表示へ流す数値観測。数値化できない場合は `nil`。
    init(valueOutcome: PIDRequestValueOutcome, sample: OBDPIDSample?) {
        self.valueOutcome = valueOutcome
        self.sample = sample
    }
}
