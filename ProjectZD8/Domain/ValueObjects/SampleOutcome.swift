/// 1件のPID要求に対する結果です。応答が無かった要求も分母として記録します。
nonisolated enum SampleOutcome: Int, Codable, CaseIterable, Sendable {
    /// データ付きの応答を受信した。
    case responded = 0
    /// 車両がデータ無し(NO DATA)と応答した。
    case noData = 1
    /// 応答待ちがタイムアウトした。
    case timedOut = 2
    /// 応答を解釈できない、または通信エラーになった。
    case failed = 3
}
