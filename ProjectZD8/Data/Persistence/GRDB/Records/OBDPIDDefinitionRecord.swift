import GRDB

/// `obd_pid_definitions` テーブルとDomain定義を相互変換するレコードです。
struct OBDPIDDefinitionRecord: Codable, FetchableRecord, PersistableRecord {
    /// 永続化先テーブル名です。
    static let databaseTableName = "obd_pid_definitions"

    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
    /// 送信先の11bit CANヘッダーです。
    let header: Int?
    /// 適用対象の車両型式です。
    let vehicleModelCode: String?
    /// 表示名の安定キーです。
    let nameKey: String
    /// 変換に必要な応答バイト数です。
    let requiredByteCount: Int?
    /// 制限付き変換数式です。
    let formula: String?
    /// 計算結果の単位です。
    let unit: String
    /// 許容最小値です。
    let minimumValue: Double?
    /// 許容最大値です。
    let maximumValue: Double?
    /// 定義根拠のURI文字列です。
    let sourceURI: String
    /// 定義の単調増加改訂番号です。
    let revision: Int
    /// 項目概要のローカライズキーです。
    let summaryKey: String
    /// 高値時説明のローカライズキーです。
    let highValueKey: String
    /// 低値時説明のローカライズキーです。
    let lowValueKey: String
    /// 相関項目説明のローカライズキーです。
    let correlationKey: String

    /// Domain定義から永続化レコードを生成します。
    ///
    /// 責務: 1件のPID Domain定義を列型へ損失なく写像します。
    /// - Parameter definition: 永続化するPID定義。
    init(definition: OBDPIDDefinition) {
        service = Int(definition.service)
        pid = Int(definition.pid)
        header = definition.header.map(Int.init)
        vehicleModelCode = definition.vehicleModelCode
        nameKey = definition.nameKey
        requiredByteCount = definition.requiredByteCount
        formula = definition.formula
        unit = definition.unit
        minimumValue = definition.minimumValue
        maximumValue = definition.maximumValue
        sourceURI = definition.sourceURI
        revision = definition.revision
        summaryKey = definition.summaryKey
        highValueKey = definition.highValueKey
        lowValueKey = definition.lowValueKey
        correlationKey = definition.correlationKey
    }

    /// 永続化列値を直接受け取ってレコードを生成します。
    ///
    /// 責務: 1件のテストまたはDB読込相当の列値をレコードへ固定します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    ///   - header: 送信先の11bit CANヘッダー。
    ///   - vehicleModelCode: 適用対象の車両型式。
    ///   - nameKey: 表示名の安定キー。
    ///   - requiredByteCount: 必要応答バイト数。
    ///   - formula: 制限付き変換数式。
    ///   - unit: 計算結果の単位。
    ///   - minimumValue: 許容最小値。
    ///   - maximumValue: 許容最大値。
    ///   - sourceURI: 定義根拠URI。
    ///   - revision: 定義改訂番号。
    ///   - summaryKey: 項目概要のローカライズキー。
    ///   - highValueKey: 高値時説明のローカライズキー。
    ///   - lowValueKey: 低値時説明のローカライズキー。
    ///   - correlationKey: 相関項目説明のローカライズキー。
    init(service: Int, pid: Int, header: Int? = nil, vehicleModelCode: String? = nil, nameKey: String, requiredByteCount: Int?, formula: String?, unit: String, minimumValue: Double?, maximumValue: Double?, sourceURI: String, revision: Int, summaryKey: String = "obd.pid.help.unconfirmed.summary", highValueKey: String = "obd.pid.help.unconfirmed.high", lowValueKey: String = "obd.pid.help.unconfirmed.low", correlationKey: String = "obd.pid.help.unconfirmed.correlation") {
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

    /// レコードをDomain定義へ変換します。
    ///
    /// 責務: 検証済みDB列を1件のPID Domain定義へ写像します。
    /// - Returns: ServiceとPIDがUInt8範囲内の場合のDomain定義。
    func makeDomainDefinition() -> OBDPIDDefinition? {
        guard let service = UInt8(exactly: service), let pid = UInt8(exactly: pid),
              header == nil || UInt16(exactly: header!) != nil else { return nil }
        return OBDPIDDefinition(
            service: service,
            pid: pid,
            header: header.flatMap(UInt16.init(exactly:)),
            vehicleModelCode: vehicleModelCode,
            nameKey: nameKey,
            requiredByteCount: requiredByteCount,
            formula: formula,
            unit: unit,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            sourceURI: sourceURI,
            revision: revision,
            summaryKey: summaryKey,
            highValueKey: highValueKey,
            lowValueKey: lowValueKey,
            correlationKey: correlationKey
        )
    }
}
