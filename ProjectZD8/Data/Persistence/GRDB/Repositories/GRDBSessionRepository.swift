import Foundation
import GRDB

/// 走行セッションとRawサンプルをGRDBで永続化します。サンプルとPIDは追記のみです。
nonisolated struct GRDBSessionRepository: SessionRepository {
    private let database: AppDatabase
    private let now: @Sendable () -> Date

    /// 責務: 共有データベースを使うリポジトリを生成します。`now` は `modifiedAt` と墓標の時刻に使います。
    init(database: AppDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.now = now
    }

    /// 責務: セッションと取得条件を1トランザクションで保存します。車両が無ければ `notFound`、同一IDが既にあれば `invalidState` を投げます。
    func begin(_ session: DriveSession, pids: [SessionPID]) async throws {
        let record = SessionRecord(session)
        let pidRecords = pids.map { SessionPIDRecord($0, sessionID: session.id) }
        try await database.storeWrite { db in
            guard try VehicleRecord.filter(Column("id") == record.vehicleID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            guard try SessionRecord.filter(Column("id") == record.id).fetchCount(db) == 0 else { throw StoreError.invalidState }
            try record.insert(db)
            for pid in pidRecords { try pid.insert(db) }
        }
    }

    /// 責務: サンプルを1トランザクションで追記し、件数・応答数・ペイロード量を加算します。`modifiedAt` は更新しません。
    func append(_ samples: [SessionSample], to id: SessionID) async throws {
        guard !samples.isEmpty else { return }
        let rowID = id.rowID
        let records = samples.map { SessionSampleRecord($0, sessionID: id) }
        let responded = samples.filter { $0.outcome == .responded }.count
        let payloadBytes = samples.reduce(0) { $0 + $1.payload.count }
        try await database.storeWrite { db in
            guard let endedAt = try Optional<Int64>.fetchOne(
                db, sql: "SELECT endedAt FROM sessions WHERE id = ? AND deletedAt IS NULL", arguments: [rowID]
            ) else {
                throw StoreError.notFound
            }
            guard endedAt == nil else { throw StoreError.invalidState }
            let insert = try db.cachedStatement(sql: """
                INSERT INTO session_samples (sessionID, sequence, tick, elapsedMicroseconds, service, pid, outcome, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for record in records {
                try insert.execute(arguments: [
                    record.sessionID, record.sequence, record.tick, record.elapsedMicroseconds,
                    record.service, record.pid, record.outcome, record.payload
                ])
            }
            let update = try db.cachedStatement(sql: """
                UPDATE sessions SET sampleCount = sampleCount + ?, respondedCount = respondedCount + ?,
                payloadByteCount = payloadByteCount + ? WHERE id = ?
                """)
            try update.execute(arguments: [records.count, responded, payloadBytes, rowID])
        }
    }

    /// 責務: 開始・終了距離と観測元を記録し、`modifiedAt` を更新します。
    func recordDistance(startKilometers: Double, endKilometers: Double, source: DistanceSource, for id: SessionID) async throws {
        let timestamp = now().epochMilliseconds
        try await database.storeWrite { db in
            try db.execute(
                sql: """
                    UPDATE sessions SET odometerStartKilometers = ?, odometerEndKilometers = ?, distanceSource = ?, modifiedAt = ?
                    WHERE id = ? AND deletedAt IS NULL
                    """,
                arguments: [startKilometers, endKilometers, source.rawValue, timestamp, id.rowID]
            )
            guard db.changesCount == 1 else { throw StoreError.notFound }
        }
    }

    /// 責務: 記録中のセッションを終了します。無ければ `notFound`、終了済みなら `invalidState` を投げます。
    func finish(_ id: SessionID, at date: Date, reason: SessionEndReason) async throws -> DriveSession {
        let rowID = id.rowID
        let timestamp = now()
        return try await database.storeWrite { db in
            guard var record = try SessionRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchOne(db) else {
                throw StoreError.notFound
            }
            guard record.endedAt == nil else { throw StoreError.invalidState }
            record.endedAt = date.epochMilliseconds
            record.endReason = reason.rawValue
            record.modifiedAt = timestamp.epochMilliseconds
            try record.update(db)
            return try record.entity()
        }
    }

    /// 責務: 記録中のまま残った全セッションを `appTerminated` で終了し、終了したセッションを返します。
    func finishUnfinishedSessions(at date: Date) async throws -> [DriveSession] {
        let timestamp = now().epochMilliseconds
        return try await database.storeWrite { db in
            let records = try SessionRecord.filter(Column("endedAt") == nil && Column("deletedAt") == nil).fetchAll(db)
            var finished: [DriveSession] = []
            for var record in records {
                record.endedAt = date.epochMilliseconds
                record.endReason = SessionEndReason.appTerminated.rawValue
                record.modifiedAt = timestamp
                try record.update(db)
                finished.append(try record.entity())
            }
            return finished
        }
    }

    /// 責務: 削除されていないセッションを開始日時の新しい順で返します。
    func sessions(for vehicleID: VehicleID?) async throws -> [DriveSession] {
        let vehicleRowID = vehicleID?.rowID
        return try await database.storeRead { db in
            var request = SessionRecord.filter(Column("deletedAt") == nil)
            if let vehicleRowID { request = request.filter(Column("vehicleID") == vehicleRowID) }
            return try request.order(Column("startedAt").desc).fetchAll(db).map { try $0.entity() }
        }
    }

    /// 責務: IDに一致する削除されていないセッションを返します。
    func session(_ id: SessionID) async throws -> DriveSession? {
        try await database.storeRead { db in
            try SessionRecord.filter(Column("id") == id.rowID && Column("deletedAt") == nil).fetchOne(db)?.entity()
        }
    }

    /// 責務: セッションの取得条件を並び順どおりに返します。
    func pids(for id: SessionID) async throws -> [SessionPID] {
        try await database.storeRead { db in
            try SessionPIDRecord.filter(Column("sessionID") == id.rowID).order(Column("ordinal")).fetchAll(db).map { try $0.entity() }
        }
    }

    /// 責務: `afterSequence` より後のサンプルを通し番号順に最大 `limit` 件返します。
    func samples(for id: SessionID, afterSequence: Int64, limit: Int) async throws -> [SessionSample] {
        try await database.storeRead { db in
            try SessionSampleRecord
                .filter(Column("sessionID") == id.rowID && Column("sequence") > afterSequence)
                .order(Column("sequence"))
                .limit(limit)
                .fetchAll(db)
                .map { try $0.entity() }
        }
    }

    /// 責務: 取得条件とサンプルを即時に削除し、セッション行を削除規則(同期済みは墓標化、未同期は物理削除)で削除します。
    func delete(_ id: SessionID) async throws {
        let rowID = id.rowID
        let timestamp = now()
        try await database.storeWrite { db in
            guard try SessionRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            try db.execute(sql: "DELETE FROM session_samples WHERE sessionID = ?", arguments: [rowID])
            try db.execute(sql: "DELETE FROM session_pids WHERE sessionID = ?", arguments: [rowID])
            try TombstoneDeletion.deleteOrTombstone(
                table: "sessions", recordType: PersistenceRecordType.driveSession, id: rowID, now: timestamp, in: db
            )
        }
    }

    /// 責務: サンプルを解放して `rawAvailability` を `cloudOnly` にします。終了済みかつアーカイブ保存済みでなければ `invalidState` を投げます。`modifiedAt` は更新しません。
    func evictSamples(for id: SessionID) async throws {
        let rowID = id.rowID
        try await database.storeWrite { db in
            guard let record = try SessionRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchOne(db) else {
                throw StoreError.notFound
            }
            guard record.endedAt != nil, record.archiveDigest != nil else { throw StoreError.invalidState }
            try db.execute(sql: "DELETE FROM session_samples WHERE sessionID = ?", arguments: [rowID])
            try db.execute(
                sql: "UPDATE sessions SET rawAvailability = ? WHERE id = ?",
                arguments: [RawAvailability.cloudOnly.rawValue, rowID]
            )
        }
    }

    /// 責務: アーカイブの内容でセッション・取得条件・サンプルを置き換えます。件数は取り込んだサンプルから再計算し、`rawAvailability` は `local` にします。車両が無ければ `notFound`、削除済みセッションなら `invalidState` を投げます。
    func importArchive(_ archive: SessionArchive) async throws {
        var record = SessionRecord(archive.session)
        record.rawAvailability = RawAvailability.local.rawValue
        record.sampleCount = archive.samples.count
        record.respondedCount = archive.samples.filter { $0.outcome == .responded }.count
        record.payloadByteCount = archive.samples.reduce(0) { $0 + $1.payload.count }
        let sessionID = archive.session.id
        let pidRecords = archive.pids.map { SessionPIDRecord($0, sessionID: sessionID) }
        let sampleRecords = archive.samples.map { SessionSampleRecord($0, sessionID: sessionID) }
        let finalRecord = record
        try await database.storeWrite { db in
            guard try VehicleRecord.filter(Column("id") == finalRecord.vehicleID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            if let existing = try SessionRecord.filter(Column("id") == finalRecord.id).fetchOne(db), existing.deletedAt != nil {
                throw StoreError.invalidState
            }
            try db.execute(sql: "DELETE FROM session_samples WHERE sessionID = ?", arguments: [finalRecord.id])
            try db.execute(sql: "DELETE FROM session_pids WHERE sessionID = ?", arguments: [finalRecord.id])
            try finalRecord.upsert(db)
            for pid in pidRecords { try pid.insert(db) }
            for sample in sampleRecords { try sample.insert(db) }
        }
    }
}
