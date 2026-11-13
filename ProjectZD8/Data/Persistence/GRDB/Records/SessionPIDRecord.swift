import GRDB

/// `session_pids` テーブルの1行です。追記のみで更新しません。
nonisolated struct SessionPIDRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "session_pids"

    var sessionID: String
    var ordinal: Int
    var service: Int
    var pid: Int
    var header: Int?
    var support: String
    var isCollectionEnabled: Bool
    var isFastGroup: Bool
    var definitionRevision: Int
    var requiredByteCount: Int?
    var formula: String?
    var unit: String
    var minimumValue: Double?
    var maximumValue: Double?

    /// 責務: セッションPIDエンティティから行を生成します。
    init(_ pid: SessionPID, sessionID: SessionID) {
        self.sessionID = sessionID.rowID
        ordinal = pid.ordinal
        service = Int(pid.request.service)
        self.pid = Int(pid.request.pid)
        header = pid.header.map { Int($0) }
        support = pid.support.rawValue
        isCollectionEnabled = pid.isCollectionEnabled
        isFastGroup = pid.isFastGroup
        definitionRevision = pid.definitionRevision
        requiredByteCount = pid.requiredByteCount
        formula = pid.formula
        unit = pid.unit
        minimumValue = pid.minimumValue
        maximumValue = pid.maximumValue
    }

    /// 責務: 行をセッションPIDエンティティへ変換します。不正な値は `StoreError.ioFailure` を投げます。
    func entity() throws -> SessionPID {
        guard
            let service = UInt8(exactly: service),
            let pidNumber = UInt8(exactly: pid),
            let support = PIDSupport(rawValue: support)
        else { throw StoreError.ioFailure }
        let canHeader = try header.map { raw -> UInt16 in
            guard let value = UInt16(exactly: raw) else { throw StoreError.ioFailure }
            return value
        }
        return SessionPID(
            ordinal: ordinal,
            request: OBDPIDRequest(service: service, pid: pidNumber),
            header: canHeader,
            support: support,
            isCollectionEnabled: isCollectionEnabled,
            isFastGroup: isFastGroup,
            definitionRevision: definitionRevision,
            requiredByteCount: requiredByteCount,
            formula: formula,
            unit: unit,
            minimumValue: minimumValue,
            maximumValue: maximumValue
        )
    }
}
