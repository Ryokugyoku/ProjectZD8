/// 1つのPIDを時系列(列指向)で表した分析用チャンネルです。
///
/// `times` と `values` は同じ長さで、応答があり変換できたサンプルだけを時刻順に並べます。
/// 欠測は補間せず、配列に含めません(0にもしません)。
nonisolated struct AnalysisChannel: Codable, Equatable, Sendable {
    /// `"<service hex>-<pid hex>"` 形式の識別値です(例: `01-0C`)。
    let id: String
    /// サービス番号の16進表記です。
    let serviceHex: String
    /// PID番号の16進表記です。
    let pidHex: String
    /// 現在の言語で解決した表示名です。
    let name: String
    /// 単位です。
    let unit: String
    /// セッション開始時に固定した宣言上の最小値です。
    let declaredMinimum: Double?
    /// セッション開始時に固定した宣言上の最大値です。
    let declaredMaximum: Double?
    /// 毎ティック取得する高頻度グループかどうかです。
    let isFast: Bool
    /// セッションへ複写した定義の改訂番号です。
    let definitionRevision: Int
    /// 変換式を持つか(値を物理量へ変換できるか)どうかです。
    let isDecodable: Bool
    /// セッション開始からの経過秒です。
    let times: [Double]
    /// 変換後の値です。
    let values: [Double]
    /// 取得品質の集計です。
    let quality: AnalysisChannelQuality
}
