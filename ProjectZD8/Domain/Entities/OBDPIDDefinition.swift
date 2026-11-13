import Foundation

/// 1つのPIDの要求方法と、応答バイトを物理値へ変換する規則を定義します。
nonisolated struct OBDPIDDefinition: Equatable, Sendable {
    /// OBDサービス番号です。
    let service: UInt8
    /// サービス内のPID番号です。
    let pid: UInt8
    /// 車種専用PIDの送信先CANヘッダーです。標準PIDでは `nil` です。
    let header: UInt16?
    /// 車種専用PIDが属する車種コードです。標準PIDでは `nil` です。
    let vehicleModelCode: String?
    /// 名称のローカライズキーです。
    let nameKey: String
    /// 数式の評価に必要な応答バイト数です。数式未確認のPIDでは `nil` です。
    let requiredByteCount: Int?
    /// 応答バイトA〜Hに適用する制限付き数式です。未確認のPIDでは `nil` です。
    let formula: String?
    /// 変換後の単位です。
    let unit: String
    /// 規格上の最小値です。
    let minimumValue: Double?
    /// 規格上の最大値です。
    let maximumValue: Double?
    /// 定義の出典です。
    let sourceURI: String
    /// 定義の改訂番号です。数式・単位・範囲を変えるたびに増やします。
    let revision: Int
    /// 概要ヘルプのローカライズキーです。
    let summaryKey: String
    /// 値が高い時のヘルプのローカライズキーです。
    let highValueKey: String
    /// 値が低い時のヘルプのローカライズキーです。
    let lowValueKey: String
    /// 関連項目ヘルプのローカライズキーです。
    let correlationKey: String

    /// PID定義を生成します。
    ///
    /// 責務: 1件のPIDの要求方法と変換規則を固定します。
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

    /// サービス番号とPID番号の組です。
    var request: OBDPIDRequest { OBDPIDRequest(service: service, pid: pid) }

    /// 応答を物理値へ変換できる定義かどうかです。
    var isDecodable: Bool { requiredByteCount != nil && formula?.isEmpty == false }

    /// 車種専用PIDかどうかです。
    var isVehicleSpecific: Bool { header != nil && vehicleModelCode?.isEmpty == false }
}
