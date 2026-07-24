import Foundation
import GRDB

/// GRDB/SQLiteへ接続セッション履歴を保存します。
final class GRDBConnectionSessionRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository, ConnectionSessionErasureRepository, AccountConnectionSessionErasureRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続をセッション履歴スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 接続セッションを保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ConnectionSessionDatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// Application Support内の製品DBを開いて生成します。
    ///
    /// 責務: 接続セッションDBの製品保存先を作成してリポジトリを返します。
    /// - Returns: Migration済みの接続セッションリポジトリ。
    /// - Throws: 保存先作成、DB接続、Migrationに失敗した場合のエラー。
    static func openApplicationRepository() throws -> GRDBConnectionSessionRepository {
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "ProjectZD8", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appending(path: "projectzd8.sqlite").path)
        return try GRDBConnectionSessionRepository(databaseQueue: queue)
    }

    /// セッションの現在内容を安定ID単位で保存します。
    ///
    /// 責務: 1件のDomain接続セッションをGRDBへ新規保存または更新します。
    /// - Parameter session: 保存する接続セッション。
    /// - Throws: SQLite書込みまたは制約確認に失敗した場合のGRDBエラー。
    func save(_ session: ConnectionSession) throws {
        try databaseQueue.write { database in
            var preservingRawState = session
            if let existing = try fetchSession(session.id, database: database) {
                preservingRawState.rawLogSummary = existing.rawLogSummary
            }
            try ConnectionSessionRecord(session: preservingRawState).save(database)
        }
    }

    /// 指定アカウントの接続セッションを新しい順で復元します。
    ///
    /// 責務: 1件のアカウント識別子に一致するGRDBレコードをDomain履歴へ復元します。
    /// - Parameter accountIdentifier: 取得対象のAppleアカウント識別子。
    /// - Returns: 開始日時が新しい順の接続セッション一覧。
    /// - Throws: SQLite読込または不正な保存値の場合のエラー。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        try databaseQueue.read { database in
            let records = try ConnectionSessionRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .order(Column("startedAt").desc)
                .fetchAll(database)
            return try records.map { record in
                guard let session = record.makeDomainSession() else {
                    throw DatabaseError(message: "Connection session contains an invalid identifier or end reason")
                }
                return try sessionWithActualLocalRawSummary(session, database: database)
            }
        }
    }

    /// 指定アカウントが所有するセッションと子Rawログを物理削除します。
    ///
    /// 責務: 1件の所有者確認済みセッションを外部キーCascade付きで原子的に物理削除します。
    /// - Parameters:
    ///   - sessionID: 削除対象の接続セッションID。
    ///   - accountIdentifier: 削除対象を所有するAppleアカウント識別子。
    /// - Throws: 所有関係不一致、セッション不在、またはSQLite削除失敗。
    func deleteSession(
        _ sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) throws {
        try databaseQueue.write { database in
            let deletedCount = try ConnectionSessionRecord
                .filter(Column("id") == sessionID.rawValue.uuidString.lowercased())
                .filter(Column("accountIdentifier") == accountIdentifier)
                .deleteAll(database)
            guard deletedCount == 1 else {
                throw ConnectionSessionRepositoryError.invalidState
            }
        }
    }

    /// 指定アカウントの接続履歴と子Rawログを削除します。
    ///
    /// 責務: 1件のアカウント識別子に属する全セッションを外部キーCascade付きで原子的に削除します。
    /// - Parameter accountIdentifier: 削除対象のAppleアカウント識別子。
    /// - Throws: SQLite削除を完了できない場合のGRDBエラー。
    func deleteSessions(for accountIdentifier: String) throws {
        try databaseQueue.write { database in
            try ConnectionSessionRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .deleteAll(database)
        }
    }

    /// 未デコードOBD応答をセッションの次の順序へ追記します。
    ///
    /// 責務: 1件のRaw応答を未終了セッションへ原子的に追加して集計値を更新します。
    /// - Parameters:
    ///   - observation: 取得境界から受け取った未デコード応答。
    ///   - sessionID: 追記対象の接続セッションID。
    /// - Throws: セッション不在、終了済み、またはSQLite書込み失敗。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {
        try databaseQueue.write { database in
            guard var session = try fetchSession(sessionID, database: database), session.endedAt == nil else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            let sessionKey = sessionID.rawValue.uuidString.lowercased()
            let sequence = try Int64.fetchOne(
                database,
                sql: "SELECT COALESCE(MAX(sequence), -1) + 1 FROM connection_session_raw_logs WHERE sessionID = ?",
                arguments: [sessionKey]
            ) ?? 0
            let entry = ConnectionSessionRawLogEntry(
                sequence: sequence,
                observedAt: observation.observedAt,
                batchElapsedNanoseconds: observation.batchElapsedNanoseconds,
                service: observation.request.service,
                pid: observation.request.pid,
                payload: observation.payload
            )
            try ConnectionSessionRawLogRecord(entry: entry, sessionID: sessionID).insert(database)
            session.rawLogSummary.recordCount += 1
            session.rawLogSummary.byteCount += Int64(observation.payload.count)
            session.rawLogSummary.localState = .available
            session.rawLogSummary.cloudState = .pending
            session.rawLogSummary.manifestDigest = nil
            session.rawLogSummary.macImportReceipt = nil
            try ConnectionSessionRecord(session: session).update(database)
        }
    }

    /// セッション内のRaw応答を記録順で復元します。
    ///
    /// 責務: 1件のセッションに属するGRDB Rawログを順序付きDomain値へ変換します。
    /// - Parameter sessionID: 読み込む接続セッションID。
    /// - Returns: `sequence`昇順の未デコードRawログ。
    /// - Throws: SQLite読込または保存値検証に失敗した場合のエラー。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] {
        try databaseQueue.read { database in
            let records = try rawLogRecords(for: sessionID, database: database)
            return try records.map { record in
                guard let entry = record.makeDomainEntry() else {
                    throw ConnectionSessionRepositoryError.integrityConflict
                }
                return entry
            }
        }
    }

    /// 指定セッションのRawログ件数をSQLite集計で返します。
    ///
    /// 責務: 1件のセッションIDを子Rawログ行の総件数へ変換します。
    /// - Parameter sessionID: 件数を取得する接続セッションID。
    /// - Returns: 保存済みRawログ行数。
    /// - Throws: SQLite集計読込に失敗した場合のエラー。
    func entryCount(for sessionID: ConnectionSessionID) throws -> Int {
        try databaseQueue.read { database in
            try ConnectionSessionRawLogRecord
                .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                .fetchCount(database)
        }
    }

    /// 指定セッションのRawログを記録順カーソルで分割して返します。
    ///
    /// 責務: 1件のセッションIDと記録順カーソルを上限付きの次ページへ変換します。
    /// - Parameters:
    ///   - sessionID: 読み込む接続セッションID。
    ///   - sequence: 直前に読み込んだ記録順序。先頭ページでは `nil`。
    ///   - limit: 1回で返す最大件数。
    /// - Returns: `sequence`昇順の次ページRawログ。
    /// - Throws: SQLite読込または保存値検証に失敗した場合のエラー。
    func entries(
        for sessionID: ConnectionSessionID,
        after sequence: Int64?,
        limit: Int
    ) throws -> [ConnectionSessionRawLogEntry] {
        try databaseQueue.read { database in
            var request = ConnectionSessionRawLogRecord
                .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
            if let sequence {
                request = request.filter(Column("sequence") > sequence)
            }
            let records = try request
                .order(Column("sequence"))
                .limit(max(0, limit))
                .fetchAll(database)
            return try records.map { record in
                guard let entry = record.makeDomainEntry() else {
                    throw ConnectionSessionRepositoryError.integrityConflict
                }
                return entry
            }
        }
    }

    /// 指定車両に属する全セッションのRaw応答を時系列で復元します。
    ///
    /// 責務: 1件のアカウントと車両IDを学習抽出可能なセッション境界付きRawログへ変換します。
    /// - Parameters:
    ///   - vehicleID: 抽出対象の登録車両ID。
    ///   - accountIdentifier: 車両とセッションを所有するAppleアカウント識別子。
    /// - Returns: セッション開始日時、セッションID、`sequence` の安定順で並ぶRawログ。
    /// - Throws: SQLite読込または保存値検証に失敗した場合のエラー。
    func entries(
        for vehicleID: VehicleID,
        accountIdentifier: String
    ) throws -> [VehicleConnectionSessionRawLogEntry] {
        try databaseQueue.read { database in
            let records = try ConnectionSessionRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .filter(Column("vehicleID") == vehicleID.rawValue.uuidString.lowercased())
                .order(Column("startedAt"), Column("id"))
                .fetchAll(database)
            return try records.flatMap { record in
                guard let session = record.makeDomainSession(), session.vehicle?.id == vehicleID else {
                    throw ConnectionSessionRepositoryError.integrityConflict
                }
                return try rawLogRecords(for: session.id, database: database).map { rawRecord in
                    guard let entry = rawRecord.makeDomainEntry() else {
                        throw ConnectionSessionRepositoryError.integrityConflict
                    }
                    return VehicleConnectionSessionRawLogEntry(
                        vehicleID: vehicleID,
                        sessionID: session.id,
                        sessionStartedAt: session.startedAt,
                        entry: entry
                    )
                }
            }
        }
    }

    /// CloudKit保存済みManifestをセッションへ記録します。
    ///
    /// 責務: 1件の終了済みセッションを指定DigestのCloudKit保存済み状態へ遷移させます。
    /// - Parameters:
    ///   - sessionID: 更新する接続セッションID。
    ///   - manifestDigest: 保存済みAssetバイトのSHA-256。
    /// - Throws: セッション状態不正またはSQLite更新失敗。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {
        try updateSession(sessionID) { session in
            guard session.endedAt != nil, !manifestDigest.isEmpty else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            session.rawLogSummary.cloudState = .uploaded
            session.rawLogSummary.manifestDigest = manifestDigest
            session.rawLogSummary.macImportReceipt = nil
        }
    }

    /// CloudKit転送失敗を再試行可能状態として記録します。
    ///
    /// 責務: 1件のRawログ保有セッションをCloudKit転送失敗状態へ遷移させます。
    /// - Parameter sessionID: 更新する接続セッションID。
    /// - Throws: セッション状態不正またはSQLite更新失敗。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {
        try updateSession(sessionID) { session in
            guard session.rawLogSummary.localState == .available else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            session.rawLogSummary.cloudState = .failed
        }
    }

    /// Mac取込受領証をセッションへ保存します。
    ///
    /// 責務: 1件のMac受領証を同じDigestのセッションManifestへ関連付けます。
    /// - Parameters:
    ///   - receipt: Macが発行した永続取込受領証。
    ///   - sessionID: 更新する接続セッションID。
    /// - Throws: Manifest不一致またはSQLite更新失敗。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {
        try updateSession(sessionID) { session in
            guard session.rawLogSummary.manifestDigest == receipt.manifestDigest else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            session.rawLogSummary.macImportReceipt = receipt
        }
    }

    /// 検証済み転送Payloadをローカル接続履歴へ取り込みます。
    ///
    /// 責務: 1件の検証済みセッションと全RawログをSQLiteへ冪等に復元します。
    /// - Parameter transfer: CloudKitから取得した検証済み転送Payload。
    /// - Throws: 順序欠損、既存Manifest不一致、またはSQLite書込み失敗。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {
        try databaseQueue.write { database in
            let package = transfer.package
            guard package.session.endedAt != nil,
                  package.entries.enumerated().allSatisfy({ Int64($0.offset) == $0.element.sequence }) else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            if let existing = try fetchSession(package.session.id, database: database) {
                let currentEntries = try rawLogRecords(for: package.session.id, database: database)
                    .compactMap { $0.makeDomainEntry() }
                if currentEntries == package.entries,
                   sessionsHaveCompatibleArchivedMetadata(existing, package.session) {
                    let reconciled = sessionByAcceptingEquivalentTransfer(
                        existing: existing,
                        transferred: package.session,
                        manifestDigest: transfer.manifestDigest,
                        entries: currentEntries
                    )
                    if reconciled != existing {
                        try ConnectionSessionRecord(session: reconciled).save(database)
                    }
                    return
                }
                if let digest = existing.rawLogSummary.manifestDigest,
                   digest != transfer.manifestDigest {
                    throw ConnectionSessionRepositoryError.integrityConflict
                }
                if existing.rawLogSummary.manifestDigest == transfer.manifestDigest {
                    let reconciled = sessionByFillingMissingTransferredMetadata(
                        existing: existing,
                        transferred: package.session
                    )
                    if reconciled != existing {
                        try ConnectionSessionRecord(session: reconciled).save(database)
                    }
                    return
                }
            }
            var imported = package.session
            imported.rawLogSummary = ConnectionSessionRawLogSummary(
                recordCount: Int64(package.entries.count),
                byteCount: package.entries.reduce(0) { $0 + Int64($1.payload.count) },
                localState: package.entries.isEmpty ? .empty : .available,
                cloudState: .uploaded,
                manifestDigest: transfer.manifestDigest,
                macImportReceipt: nil
            )
            try ConnectionSessionRecord(session: imported).save(database)
            try ConnectionSessionRawLogRecord
                .filter(Column("sessionID") == imported.id.rawValue.uuidString.lowercased())
                .deleteAll(database)
            for entry in package.entries {
                try ConnectionSessionRawLogRecord(entry: entry, sessionID: imported.id).insert(database)
            }
            guard try fetchSession(imported.id, database: database) == imported else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            let readBackEntries = try rawLogRecords(for: imported.id, database: database)
                .compactMap { $0.makeDomainEntry() }
            guard readBackEntries == package.entries else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
        }
    }

    /// Manifestだけが異なる同内容転送を現在端末の検証済み状態へ反映します。
    ///
    /// 責務: 同じRawログと互換メタデータを持つ既存セッションを受信Manifestへ非破壊で整合させます。
    /// - Parameters:
    ///   - existing: 現在端末に保存済みのセッション。
    ///   - transferred: CloudKitから復元した同内容セッション。
    ///   - manifestDigest: 検証済み転送PayloadのSHA-256。
    ///   - entries: 両者で一致した未デコードRawログ。
    /// - Returns: ローカル表示情報を保持し、転送Manifestと集計を反映したセッション。
    private func sessionByAcceptingEquivalentTransfer(
        existing: ConnectionSession,
        transferred: ConnectionSession,
        manifestDigest: String,
        entries: [ConnectionSessionRawLogEntry]
    ) -> ConnectionSession {
        var reconciled = sessionByFillingMissingTransferredMetadata(
            existing: existing,
            transferred: transferred
        )
        reconciled.rawLogSummary.recordCount = Int64(entries.count)
        reconciled.rawLogSummary.byteCount = entries.reduce(0) { $0 + Int64($1.payload.count) }
        reconciled.rawLogSummary.cloudState = .uploaded
        reconciled.rawLogSummary.manifestDigest = manifestDigest
        if reconciled.rawLogSummary.macImportReceipt?.manifestDigest != manifestDigest {
            reconciled.rawLogSummary.macImportReceipt = nil
        }
        return reconciled
    }

    /// 2件のセッションが同じ保存済み運転を表現できるかを確認します。
    ///
    /// 責務: セッション識別情報と両側に存在する取得メタデータを同内容転送判定へ変換します。
    /// - Parameters:
    ///   - existing: 現在端末に保存済みのセッション。
    ///   - transferred: CloudKitから復元したセッション。
    /// - Returns: 必須情報が一致し、任意情報に矛盾がない場合は `true`。
    private func sessionsHaveCompatibleArchivedMetadata(
        _ existing: ConnectionSession,
        _ transferred: ConnectionSession
    ) -> Bool {
        existing.id == transferred.id
            && existing.accountIdentifier == transferred.accountIdentifier
            && existing.startedAt == transferred.startedAt
            && existing.endedAt == transferred.endedAt
            && existing.endReason == transferred.endReason
            && valuesAreCompatible(existing.vehicle, transferred.vehicle)
            && valuesAreCompatible(existing.acquisitionDevice, transferred.acquisitionDevice)
            && valuesAreCompatible(existing.startingOdometerKilometers, transferred.startingOdometerKilometers)
            && valuesAreCompatible(existing.endingOdometerKilometers, transferred.endingOdometerKilometers)
            && valuesAreCompatible(existing.distanceSourceModelCode, transferred.distanceSourceModelCode)
    }

    /// 2件の任意値が欠落補完可能または同値かを返します。
    ///
    /// 責務: 任意の同型値2件を非破壊なメタデータ補完可否へ変換します。
    /// - Parameters:
    ///   - lhs: 現在端末の任意値。
    ///   - rhs: 転送Payloadの任意値。
    /// - Returns: 片方が欠落しているか両方が同値の場合は `true`。
    private func valuesAreCompatible<Value: Equatable>(_ lhs: Value?, _ rhs: Value?) -> Bool {
        lhs == nil || rhs == nil || lhs == rhs
    }

    /// 同じManifestの転送情報でローカル欠落メタデータだけを補完します。
    ///
    /// 責務: 1件の既存セッションへ同一転送Payloadが保持する欠落中の表示情報を非破壊で反映します。
    /// - Parameters:
    ///   - existing: 端末固有の保管状態と後続確認結果を保持する既存セッション。
    ///   - transferred: 同じManifestから復元した転送時点のセッション。
    /// - Returns: ローカル値を優先し、欠落項目だけを転送値で補完したセッション。
    private func sessionByFillingMissingTransferredMetadata(
        existing: ConnectionSession,
        transferred: ConnectionSession
    ) -> ConnectionSession {
        var reconciled = existing
        if reconciled.vehicle == nil {
            reconciled.vehicle = transferred.vehicle
        }
        if reconciled.acquisitionDevice == nil {
            reconciled.acquisitionDevice = transferred.acquisitionDevice
        }
        if reconciled.startingOdometerKilometers == nil {
            reconciled.startingOdometerKilometers = transferred.startingOdometerKilometers
        }
        if reconciled.endingOdometerKilometers == nil {
            reconciled.endingOdometerKilometers = transferred.endingOdometerKilometers
        }
        if reconciled.distanceSourceModelCode == nil {
            reconciled.distanceSourceModelCode = transferred.distanceSourceModelCode
        }
        return reconciled
    }

    /// セッション概要を残して現在端末のRawログだけを除去します。
    ///
    /// 責務: 1件の終了済みセッションからRawログ行だけを削除してローカル除去状態へ遷移させます。
    /// - Parameter sessionID: RawログPayloadを除去する接続セッションID。
    /// - Throws: 取得中、Rawログ不在、またはSQLite更新失敗。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws {
        try databaseQueue.write { database in
            guard var session = try fetchSession(sessionID, database: database),
                  session.endedAt != nil,
                  session.rawLogSummary.localState == .available else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            try ConnectionSessionRawLogRecord
                .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                .deleteAll(database)
            session.rawLogSummary.localState = .removed
            try ConnectionSessionRecord(session: session).update(database)
        }
    }

    /// 指定セッションを読み込み、変更処理を同一SQLite書込み内で保存します。
    ///
    /// 責務: 1件のセッション状態更新を読込と保存の原子的境界へ変換します。
    /// - Parameters:
    ///   - sessionID: 更新する接続セッションID。
    ///   - transform: 読み込んだDomainセッションへ適用する変更。
    /// - Throws: セッション不在、変更拒否、またはSQLite更新失敗。
    private func updateSession(
        _ sessionID: ConnectionSessionID,
        transform: (inout ConnectionSession) throws -> Void
    ) throws {
        try databaseQueue.write { database in
            guard var session = try fetchSession(sessionID, database: database) else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            try transform(&session)
            try ConnectionSessionRecord(session: session).update(database)
        }
    }

    /// SQLiteから1件のDomain接続セッションを復元します。
    ///
    /// 責務: 1件の接続セッションIDを検証済みDomainセッションへ変換します。
    /// - Parameters:
    ///   - sessionID: 取得する接続セッションID。
    ///   - database: 現在のSQLiteアクセス境界。
    /// - Returns: 保存済みの場合のDomain接続セッション。
    /// - Throws: SQLite読込または保存値検証に失敗した場合のエラー。
    private func fetchSession(_ sessionID: ConnectionSessionID, database: Database) throws -> ConnectionSession? {
        let key = sessionID.rawValue.uuidString.lowercased()
        guard let record = try ConnectionSessionRecord.fetchOne(database, key: key) else { return nil }
        guard let session = record.makeDomainSession() else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return session
    }

    /// SQLiteから1件のセッションに属するRawログレコードを取得します。
    ///
    /// 責務: 1件の接続セッションIDを記録順のGRDB Rawログ配列へ変換します。
    /// - Parameters:
    ///   - sessionID: 取得する接続セッションID。
    ///   - database: 現在のSQLiteアクセス境界。
    /// - Returns: `sequence`昇順のGRDB Rawログレコード。
    /// - Throws: SQLite読込に失敗した場合のエラー。
    private func rawLogRecords(
        for sessionID: ConnectionSessionID,
        database: Database
    ) throws -> [ConnectionSessionRawLogRecord] {
        try ConnectionSessionRawLogRecord
            .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
            .order(Column("sequence"))
            .fetchAll(database)
    }

    /// ローカルRawを保持するセッションの表示集計を子テーブル実レコードから復元します。
    ///
    /// 責務: 1件のセッション概要を現在のRaw子行件数とPayload合計へ補正します。
    /// - Parameters:
    ///   - session: 補正対象の接続セッション。
    ///   - database: 現在のSQLiteアクセス境界。
    /// - Returns: ローカルRawがある場合に実レコード集計を反映したセッション。
    /// - Throws: SQLite集計読込に失敗した場合のエラー。
    private func sessionWithActualLocalRawSummary(
        _ session: ConnectionSession,
        database: Database
    ) throws -> ConnectionSession {
        guard session.rawLogSummary.localState != .removed else { return session }
        let key = session.id.rawValue.uuidString.lowercased()
        let row = try Row.fetchOne(
            database,
            sql: "SELECT COUNT(*) AS recordCount, COALESCE(SUM(length(payload)), 0) AS byteCount FROM connection_session_raw_logs WHERE sessionID = ?",
            arguments: [key]
        )
        var corrected = session
        corrected.rawLogSummary.recordCount = row?["recordCount"] ?? 0
        corrected.rawLogSummary.byteCount = row?["byteCount"] ?? 0
        if corrected.rawLogSummary.recordCount > 0 {
            corrected.rawLogSummary.localState = .available
        }
        return corrected
    }
}
