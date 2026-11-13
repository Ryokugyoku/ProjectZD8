/// 1つのチャンネルについて、要求がどう終わったかの集計です。
nonisolated struct AnalysisChannelQuality: Codable, Equatable, Sendable {
    /// 発行した要求の総数です。
    var requested: Int
    /// データ付きで応答した要求の数です。
    var responded: Int
    /// 車両が NO DATA と応答した要求の数です。
    var noData: Int
    /// 応答待ちがタイムアウトした要求の数です。
    var timedOut: Int
    /// 応答を解釈できない、または通信エラーになった要求の数です。
    var failed: Int
    /// 応答を物理値へ変換でき、宣言範囲内だったサンプル数です(値配列の長さと一致します)。
    var decoded: Int
    /// 応答したが式の評価に失敗した(バイト不足など)サンプル数です。値配列には含めません。
    var undecodable: Int
    /// 変換できたが宣言範囲外だったサンプル数です。値配列には含めません。
    var outOfRange: Int

    /// 全て0の集計を生成します。
    ///
    /// 責務: チャンネルの品質集計を空の状態で初期化します。
    init(requested: Int = 0, responded: Int = 0, noData: Int = 0, timedOut: Int = 0, failed: Int = 0, decoded: Int = 0, undecodable: Int = 0, outOfRange: Int = 0) {
        self.requested = requested
        self.responded = responded
        self.noData = noData
        self.timedOut = timedOut
        self.failed = failed
        self.decoded = decoded
        self.undecodable = undecodable
        self.outOfRange = outOfRange
    }
}
