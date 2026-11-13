import Foundation
import GRDB

/// セッションのRawをアーカイブとして取り出し、ダウンロードしたアーカイブをローカルへ復元します。
nonisolated struct SyncSessionArchiveStore: Sendable {
    private let database: AppDatabase

    /// 責務: 共有データベースを読み書きするストアを生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 終了済み・デモ以外・Rawがローカルにあるセッションの完全なアーカイブを作ります。
    /// - Returns: 対象外(記録中・デモ・Rawが端末に無い・削除済み)なら `nil`。
    /// - Throws: 読み込み失敗、または列の値が不正な場合のエラー。
    func makeArchive(sessionID: String) throws -> SessionArchive? {
        try database.writer.read { db in
            guard let row = try SyncSessionRow.fetchOne(db, key: sessionID),
                  row.deletedAt == nil, row.isSyncable,
                  row.rawAvailability == RawAvailability.local.rawValue else { return nil }
            let pids = try SyncSessionPIDRow
                .filter(Column("sessionID") == sessionID)
                .order(Column("ordinal"))
                .fetchAll(db)
                .map(Self.sessionPID(from:))
            let samples = try SyncSessionSampleRow
                .filter(Column("sessionID") == sessionID)
                .order(Column("sequence"))
                .fetchAll(db)
                .map(Self.sessionSample(from:))
            var session = try Self.driveSession(from: row)
            session.archiveDigest = nil
            return SessionArchive(session: session, pids: pids, samples: samples)
        }
    }

    /// 責務: 復元対象のセッションのRawの所在と検証値を返します。行が無いか削除済みなら `nil` です。
    func restoreTarget(sessionID: String) throws -> (rawAvailability: RawAvailability, archiveDigest: String?)? {
        try database.writer.read { db in
            guard let row = try SyncSessionRow.fetchOne(db, key: sessionID), row.deletedAt == nil else { return nil }
            guard let availability = RawAvailability(rawValue: row.rawAvailability) else {
                throw SyncLocalStoreError.invalidValue("rawAvailability")
            }
            return (availability, row.archiveDigest)
        }
    }

    /// 責務: 検証済みアーカイブのPIDとサンプルを1トランザクションで書き込み、Rawをローカル扱いにします。
    ///
    /// セッションの属性と `modifiedAt` は変えません(Rawの所在は端末ローカルの情報で同期しないため)。
    /// - Throws: セッション行が無い場合は `SyncLocalStoreError.rowNotFound`、書き込み失敗時はデータベースエラー。
    func restore(_ archive: SessionArchive) throws {
        let sessionID = archive.session.id.rawValue.uuidString.lowercased()
        try database.writer.write { db in
            guard let row = try SyncSessionRow.fetchOne(db, key: sessionID), row.deletedAt == nil else {
                throw SyncLocalStoreError.rowNotFound
            }
            try SyncSessionSampleRow.filter(Column("sessionID") == sessionID).deleteAll(db)
            try SyncSessionPIDRow.filter(Column("sessionID") == sessionID).deleteAll(db)
            for pid in archive.pids {
                try Self.pidRow(pid, sessionID: sessionID).insert(db)
            }
            for sample in archive.samples {
                try Self.sampleRow(sample, sessionID: sessionID).insert(db)
            }
            try db.execute(
                sql: "UPDATE sessions SET rawAvailability = ? WHERE id = ?",
                arguments: [RawAvailability.local.rawValue, sessionID]
            )
        }
    }

    /// 責務: セッション行をDomainのセッションへ変換します。
    static func driveSession(from row: SyncSessionRow) throws -> DriveSession {
        guard let id = UUID(uuidString: row.id) else { throw SyncLocalStoreError.invalidValue("id") }
        guard let vehicleID = UUID(uuidString: row.vehicleID) else { throw SyncLocalStoreError.invalidValue("vehicleID") }
        guard let transport = AdapterTransport(rawValue: row.adapterTransport) else { throw SyncLocalStoreError.invalidValue("adapterTransport") }
        guard let platform = AcquisitionPlatform(rawValue: row.platform) else { throw SyncLocalStoreError.invalidValue("platform") }
        guard let availability = RawAvailability(rawValue: row.rawAvailability) else { throw SyncLocalStoreError.invalidValue("rawAvailability") }
        let endReason = try row.endReason.map { raw in
            guard let reason = SessionEndReason(rawValue: raw) else { throw SyncLocalStoreError.invalidValue("endReason") }
            return reason
        }
        let distanceSource = try row.distanceSource.map { raw in
            guard let source = DistanceSource(rawValue: raw) else { throw SyncLocalStoreError.invalidValue("distanceSource") }
            return source
        }
        return DriveSession(
            id: SessionID(rawValue: id),
            vehicleID: VehicleID(rawValue: vehicleID),
            startedAt: date(row.startedAt),
            endedAt: row.endedAt.map(date),
            endReason: endReason,
            isDemo: row.isDemo,
            adapterName: row.adapterName,
            adapterTransport: transport,
            platform: platform,
            deviceID: row.deviceID,
            deviceName: row.deviceName,
            appVersion: row.appVersion,
            appBuild: row.appBuild,
            pollingPolicyVersion: row.pollingPolicyVersion,
            odometerStartKilometers: row.odometerStartKilometers,
            odometerEndKilometers: row.odometerEndKilometers,
            distanceSource: distanceSource,
            sampleCount: row.sampleCount,
            respondedCount: row.respondedCount,
            payloadByteCount: row.payloadByteCount,
            rawAvailability: availability,
            archiveDigest: row.archiveDigest,
            modifiedAt: date(row.modifiedAt)
        )
    }

    /// 責務: PID行をDomainのセッションPIDへ変換します。
    static func sessionPID(from row: SyncSessionPIDRow) throws -> SessionPID {
        guard let support = PIDSupport(rawValue: row.support) else { throw SyncLocalStoreError.invalidValue("support") }
        guard let service = UInt8(exactly: row.service), let pid = UInt8(exactly: row.pid) else {
            throw SyncLocalStoreError.invalidValue("service/pid")
        }
        let header = try row.header.map { raw in
            guard let value = UInt16(exactly: raw) else { throw SyncLocalStoreError.invalidValue("header") }
            return value
        }
        return SessionPID(
            ordinal: row.ordinal,
            request: OBDPIDRequest(service: service, pid: pid),
            header: header,
            support: support,
            isCollectionEnabled: row.isCollectionEnabled,
            isFastGroup: row.isFastGroup,
            definitionRevision: row.definitionRevision,
            requiredByteCount: row.requiredByteCount,
            formula: row.formula,
            unit: row.unit,
            minimumValue: row.minimumValue,
            maximumValue: row.maximumValue
        )
    }

    /// 責務: サンプル行をDomainのサンプルへ変換します。
    static func sessionSample(from row: SyncSessionSampleRow) throws -> SessionSample {
        guard let outcome = SampleOutcome(rawValue: row.outcome) else { throw SyncLocalStoreError.invalidValue("outcome") }
        guard let service = UInt8(exactly: row.service), let pid = UInt8(exactly: row.pid) else {
            throw SyncLocalStoreError.invalidValue("service/pid")
        }
        return SessionSample(
            sequence: row.sequence,
            tick: row.tick,
            elapsedMicroseconds: row.elapsedMicroseconds,
            request: OBDPIDRequest(service: service, pid: pid),
            outcome: outcome,
            payload: row.payload
        )
    }

    /// 責務: セッションPIDを指定セッションのPID行へ変換します。
    static func pidRow(_ pid: SessionPID, sessionID: String) -> SyncSessionPIDRow {
        SyncSessionPIDRow(
            sessionID: sessionID,
            ordinal: pid.ordinal,
            service: Int(pid.request.service),
            pid: Int(pid.request.pid),
            header: pid.header.map(Int.init),
            support: pid.support.rawValue,
            isCollectionEnabled: pid.isCollectionEnabled,
            isFastGroup: pid.isFastGroup,
            definitionRevision: pid.definitionRevision,
            requiredByteCount: pid.requiredByteCount,
            formula: pid.formula,
            unit: pid.unit,
            minimumValue: pid.minimumValue,
            maximumValue: pid.maximumValue
        )
    }

    /// 責務: サンプルを指定セッションのサンプル行へ変換します。
    static func sampleRow(_ sample: SessionSample, sessionID: String) -> SyncSessionSampleRow {
        SyncSessionSampleRow(
            sessionID: sessionID,
            sequence: sample.sequence,
            tick: sample.tick,
            elapsedMicroseconds: sample.elapsedMicroseconds,
            service: Int(sample.request.service),
            pid: Int(sample.request.pid),
            outcome: sample.outcome.rawValue,
            payload: sample.payload
        )
    }

    /// 責務: エポックミリ秒を日時へ変換します。
    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
