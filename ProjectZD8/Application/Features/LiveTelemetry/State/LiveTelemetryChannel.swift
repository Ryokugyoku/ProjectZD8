import Foundation

/// 1つのPIDのリアルタイム表示用の状態です。
nonisolated struct LiveTelemetryChannel: Identifiable, Equatable, Sendable {
    /// 直近の値の状態です。
    nonisolated enum Validity: Equatable, Sendable {
        /// まだ1度も値が届いていません。
        case awaiting
        /// 規格範囲内の有効な値です。
        case valid
        /// 変換できましたが規格範囲外です。
        case outOfRange(Double)
        /// 応答を変換できませんでした。
        case decodeFailed
        /// データ付き応答がありませんでした。
        case noResponse(SampleOutcome)
    }

    /// 履歴の1点です。
    nonisolated struct Point: Equatable, Sendable {
        /// セッション開始からの経過時間(マイクロ秒)です。
        let elapsedMicroseconds: Int64
        let value: Double
    }

    /// 履歴として保持する時間(マイクロ秒)です。
    static let historyDurationMicroseconds: Int64 = 120_000_000

    var id: OBDPIDRequest { request }
    let request: OBDPIDRequest
    /// セッション内の並び順です。
    let ordinal: Int
    /// 名称のローカライズキーです。
    let nameKey: String
    let unit: String
    let category: OBDPIDCategory
    /// 規格上の最小値です。
    let minimumValue: Double?
    /// 規格上の最大値です。
    let maximumValue: Double?
    /// 直近の値の状態です。
    private(set) var validity: Validity = .awaiting
    /// 直近の有効な値です。`validity` が `valid` の時だけ値を持ち、無効な時に 0 などを代入しません。
    private(set) var value: Double?
    /// 直近120秒の有効な値の履歴です。古い順に並びます。
    private(set) var history: [Point] = []

    /// 責務: 値が届く前のチャンネルを生成します。
    init(spec: LiveTelemetryEvent.ChannelSpec) {
        request = spec.request
        ordinal = spec.ordinal
        nameKey = spec.nameKey
        unit = spec.unit
        minimumValue = spec.minimumValue
        maximumValue = spec.maximumValue
        category = Self.category(for: spec)
    }

    /// 責務: 届いた値を反映し、有効な値だけを履歴へ加えて120秒より古い点を捨てます。
    mutating func apply(_ reading: LiveTelemetryEvent.Reading, at elapsedMicroseconds: Int64) {
        switch reading {
        case .value(let value):
            validity = .valid
            self.value = value
            history.append(Point(elapsedMicroseconds: elapsedMicroseconds, value: value))
            let cutoff = elapsedMicroseconds - Self.historyDurationMicroseconds
            let expired = history.prefix { $0.elapsedMicroseconds < cutoff }.count
            if expired > 0 { history.removeFirst(expired) }
        case .outOfRange(let value):
            validity = .outOfRange(value)
            self.value = nil
        case .decodeFailed:
            validity = .decodeFailed
            value = nil
        case .noResponse(let outcome):
            validity = .noResponse(outcome)
            value = nil
        }
    }

    /// 責務: 標準PIDは `OBDPIDCategory` で、車種専用PIDは単位で分類します。
    private static func category(for spec: LiveTelemetryEvent.ChannelSpec) -> OBDPIDCategory {
        if spec.request.service == 0x01 { return OBDPIDCategory.category(for: spec.request) }
        return spec.unit == "°C" ? .temperature : .diagnostics
    }
}
