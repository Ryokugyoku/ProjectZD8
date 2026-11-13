import Foundation

/// 1件の標準OBD PIDを数値へ変換するための永続化可能な定義です。
nonisolated struct OBDPIDDefinition: Equatable, Sendable {
    /// OBD要求のService番号です。
    let service: UInt8
    /// Service内のPID番号です。
    let pid: UInt8
    /// 送信先ECUを固定する11bit CANヘッダーです。標準機能アドレスの場合は `nil` です。
    let header: UInt16?
    /// この定義を使用できる車両型式です。標準PIDの場合は `nil` です。
    let vehicleModelCode: String?
    /// 表示名へ解決できる安定キーです。
    let nameKey: String
    /// 数式が参照する応答データの必要バイト数です。
    let requiredByteCount: Int?
    /// `A`から`H`までのバイト変数を使用する制限付き数式です。
    let formula: String?
    /// 計算結果の単位です。
    let unit: String
    /// 規格上または定義上の最小値です。
    let minimumValue: Double?
    /// 規格上または定義上の最大値です。
    let maximumValue: Double?
    /// 定義を確認した一次資料のURI文字列です。
    let sourceURI: String
    /// 同じService/PID定義を更新するときの単調増加改訂番号です。
    let revision: Int
    /// 項目概要を表示するローカライズキーです。
    let summaryKey: String
    /// 高値時の確認観点を表示するローカライズキーです。
    let highValueKey: String
    /// 低値時の確認観点を表示するローカライズキーです。
    let lowValueKey: String
    /// 関連項目を表示するローカライズキーです。
    let correlationKey: String

    /// 数式を含むPID定義を生成します。
    ///
    /// 責務: 1件のPID識別子と変換契約を不変値として固定します。
    /// - Parameters:
    ///   - service: OBD要求のService番号。
    ///   - pid: Service内のPID番号。
    ///   - header: 送信先ECUを固定する11bit CANヘッダー。
    ///   - vehicleModelCode: この定義を使用できる車両型式。
    ///   - nameKey: 表示名の安定キー。
    ///   - requiredByteCount: 数式評価に必要なバイト数。
    ///   - formula: 制限付き数式。
    ///   - unit: 計算結果の単位。
    ///   - minimumValue: 許容最小値。
    ///   - maximumValue: 許容最大値。
    ///   - sourceURI: 一次資料のURI文字列。
    ///   - revision: 定義の改訂番号。
    ///   - summaryKey: 項目概要のローカライズキー。
    ///   - highValueKey: 高値時説明のローカライズキー。
    ///   - lowValueKey: 低値時説明のローカライズキー。
    ///   - correlationKey: 相関項目説明のローカライズキー。
    init(
        service: UInt8,
        pid: UInt8,
        header: UInt16? = nil,
        vehicleModelCode: String? = nil,
        nameKey: String,
        requiredByteCount: Int?,
        formula: String?,
        unit: String,
        minimumValue: Double?,
        maximumValue: Double?,
        sourceURI: String,
        revision: Int,
        summaryKey: String = "obd.pid.help.unconfirmed.summary",
        highValueKey: String = "obd.pid.help.unconfirmed.high",
        lowValueKey: String = "obd.pid.help.unconfirmed.low",
        correlationKey: String = "obd.pid.help.unconfirmed.correlation"
    ) {
        self.service = service
        self.pid = pid
        self.header = header
        self.vehicleModelCode = vehicleModelCode
        self.nameKey = nameKey
        self.requiredByteCount = requiredByteCount
        self.formula = formula
        self.unit = unit
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.sourceURI = sourceURI
        self.revision = revision
        self.summaryKey = summaryKey
        self.highValueKey = highValueKey
        self.lowValueKey = lowValueKey
        self.correlationKey = correlationKey
    }

    /// 定義式で安全に数値化できるPIDかどうかです。
    var isDecodable: Bool { requiredByteCount != nil && formula?.isEmpty == false }

    /// 特定車両だけへ要求できる拡張PIDかどうかです。
    var isVehicleSpecific: Bool { header != nil && vehicleModelCode?.isEmpty == false }
}
