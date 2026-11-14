import Foundation
import GRDB
import OSLog

/// GRDB/SQLiteへ取得チャンクのRawと取得証跡を1つの書き込みトランザクションで保存します。
nonisolated final class GRDBConnectionSessionAcquisitionChunkRepository: ConnectionSessionAcquisitionChunkRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// 採番済みRawの追加と親セッション集計の更新を担う既存の書き込み部品です。
    private let rawLogAppender = GRDBConnectionSessionRawLogAppender()
    /// GRDB詳細を内向き診断へ保持するloggerです。
    private let logger = Logger(subsystem: "ProjectZD8", category: "AcquisitionChunkPersistence")

    /// 指定DB Queueへ全forward-only migrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続をRawと取得証跡のスキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: チャンクを保存するDB Queue。
    /// - Throws: migration失敗を `ConnectionSessionAcquisitionChunkRepositoryError.unavailable` として返します。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        do {
            try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
        } catch {
            logger.error("取得チャンクmigration失敗: \(String(describing: error), privacy: .private)")
            throw ConnectionSessionAcquisitionChunkRepositoryError.unavailable
        }
    }

    /// チャンク内のRawと取得証跡をすべて保存するか、何も保存しません。
    ///
    /// 責務: チャンクを検証し、Raw、batch、requestを1つの書き込みトランザクションで保存します。
    /// - Parameter chunk: 保存するチャンク。空なら何も書かずに正常終了します。
    /// - Throws: 検証失敗または保存失敗を表す `ConnectionSessionAcquisitionChunkRepositoryError`。
    ///   トランザクション内で失敗した場合はチャンク全体をロールバックします。
    func commit(_ chunk: ConnectionSessionAcquisitionChunk) throws {
        guard !chunk.isEmpty else { return }
        do {
            try validateContents(of: chunk)
            let sessionKey = chunk.sessionID.rawValue.uuidString.lowercased()
            try databaseQueue.write { database in
                let session = try openSession(chunk.sessionID, database: database)
                try validateRawEntriesAgainstStoredRows(chunk, sessionKey: sessionKey, database: database)
                try rawLogAppender.insertNumbered(chunk.rawEntries, into: session, in: database)
                try validateBatchesAgainstStoredRows(chunk, sessionKey: sessionKey, database: database)
                try insertBatches(chunk.batches, sessionKey: sessionKey, database: database)
            }
        } catch {
            throw translatedError(error)
        }
    }

    /// DBを読まずに判定できるチャンク内の整合性を検証します。
    ///
    /// 責務: Rawの時刻情報の欠落・連番重複と、batchの未確定・番号重複を拒否します。
    /// - Parameter chunk: 検証するチャンク。
    /// - Throws: 最初に見つかった違反に対応する `ConnectionSessionAcquisitionChunkRepositoryError`。
    private func validateContents(of chunk: ConnectionSessionAcquisitionChunk) throws {
        guard chunk.rawEntries.allSatisfy({ $0.monotonicNanoseconds != nil && $0.segmentOrdinal != nil }) else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.rawTimingMissing
        }
        guard Set(chunk.rawEntries.map(\.sequence)).count == chunk.rawEntries.count else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.duplicateSequenceInChunk
        }
        guard chunk.batches.allSatisfy({ $0.completionState != nil }) else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.batchNotTerminal
        }
        guard Set(chunk.batches.map(\.identity.ordinal)).count == chunk.batches.count else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.duplicateBatchInChunk
        }
    }

    /// チャンクを所有する未終了セッションを読み取ります。
    ///
    /// 責務: セッションの不在と終了済みを区別して拒否し、保存に使う現在値を返します。
    /// - Parameters:
    ///   - sessionID: チャンクを所有する接続セッション。
    ///   - database: 現在の書き込みトランザクション。
    /// - Returns: 未終了の接続セッション。
    /// - Throws: 不在は `.sessionNotFound`、終了済みは `.sessionEnded`、保存値破損は整合性エラー。
    private func openSession(_ sessionID: ConnectionSessionID, database: Database) throws -> ConnectionSession {
        guard let session = try rawLogAppender.fetchSession(sessionID, database: database) else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.sessionNotFound
        }
        guard session.endedAt == nil else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.sessionEnded
        }
        return session
    }

    /// チャンクのRawが保存済み行・セグメントと矛盾しないことを検証します。
    ///
    /// 責務: 保存済み連番との重複と、開始を保存していないセグメントへの所属を拒否します。
    /// - Parameters:
    ///   - chunk: 検証するチャンク。
    ///   - sessionKey: 親セッションのDB key。
    ///   - database: 現在の書き込みトランザクション。
    /// - Throws: 重複は `.sequenceAlreadyStored`、未開始セグメントは `.segmentNotStarted`。
    private func validateRawEntriesAgainstStoredRows(
        _ chunk: ConnectionSessionAcquisitionChunk,
        sessionKey: String,
        database: Database
    ) throws {
        guard !chunk.rawEntries.isEmpty else { return }
        let sequences = chunk.rawEntries.map(\.sequence)
        guard try storedRawCount(sequences: sequences, sessionKey: sessionKey, database: database) == 0 else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.sequenceAlreadyStored
        }
        let segmentOrdinals = Array(Set(chunk.rawEntries.compactMap(\.segmentOrdinal))).map(Int64.init)
        let startedSegmentCount = try ConnectionSessionSegmentRecord
            .filter(Column("sessionID") == sessionKey && segmentOrdinals.contains(Column("segmentOrdinal")))
            .fetchCount(database)
        guard startedSegmentCount == segmentOrdinals.count else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.segmentNotStarted
        }
    }

    /// チャンクのbatchが保存済みの取得証跡と矛盾しないことを検証します。
    ///
    /// 責務: 確定manifestの欠落、保存済みbatch番号との重複、存在しないRawへの参照を拒否します。
    /// - Parameters:
    ///   - chunk: 検証するチャンク。Rawは同じトランザクションで保存済みです。
    ///   - sessionKey: 親セッションのDB key。
    ///   - database: 現在の書き込みトランザクション。
    /// - Throws: `.acquisitionStartMissing`、`.batchAlreadyStored`、`.rawReferenceMissing` のいずれか。
    private func validateBatchesAgainstStoredRows(
        _ chunk: ConnectionSessionAcquisitionChunk,
        sessionKey: String,
        database: Database
    ) throws {
        guard !chunk.batches.isEmpty else { return }
        let sealedManifestCount = try ConnectionSessionAcquisitionManifestRecord
            .filter(Column("sessionID") == sessionKey && Column("isSealed") == true)
            .fetchCount(database)
        guard sealedManifestCount == 1 else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.acquisitionStartMissing
        }
        let batchOrdinals = chunk.batches.map(\.identity.ordinal)
        let storedBatchCount = try ConnectionSessionAcquisitionBatchRecord
            .filter(Column("sessionID") == sessionKey && batchOrdinals.contains(Column("batchOrdinal")))
            .fetchCount(database)
        guard storedBatchCount == 0 else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.batchAlreadyStored
        }
        let referencedSequences = Array(Set(chunk.batches.flatMap(\.requests).compactMap(\.rawSequence)))
        let referencedRawCount = try storedRawCount(
            sequences: referencedSequences,
            sessionKey: sessionKey,
            database: database
        )
        guard referencedRawCount == referencedSequences.count else {
            throw ConnectionSessionAcquisitionChunkRepositoryError.rawReferenceMissing
        }
    }

    /// 指定連番のうちセッションに保存済みのRaw行数を返します。
    ///
    /// 責務: 1件のセッションに属するRaw行を連番集合で数えます。
    /// - Parameters:
    ///   - sequences: 数える対象の連番。
    ///   - sessionKey: 親セッションのDB key。
    ///   - database: 現在のSQLite境界。
    /// - Returns: 保存済みの行数。
    /// - Throws: SQLite読取失敗。
    private func storedRawCount(sequences: [Int64], sessionKey: String, database: Database) throws -> Int {
        guard !sequences.isEmpty else { return 0 }
        return try ConnectionSessionRawLogRecord
            .filter(Column("sessionID") == sessionKey && sequences.contains(Column("sequence")))
            .fetchCount(database)
    }

    /// 終端状態まで確定したbatchとそのrequestを保存します。
    ///
    /// 責務: 既存のbatch/request保存表現を使い、各batchをseal済みの行として追加します。
    /// - Parameters:
    ///   - batches: 保存する終端batch。
    ///   - sessionKey: 親セッションのDB key。
    ///   - database: 現在の書き込みトランザクション。
    /// - Throws: 値の範囲外は整合性エラー、DB制約違反はGRDBエラー。
    private func insertBatches(_ batches: [AcquisitionBatchEvidence], sessionKey: String, database: Database) throws {
        for batch in batches {
            try ConnectionSessionAcquisitionBatchRecord(evidence: batch, sessionID: sessionKey).insert(database)
            for request in batch.requests {
                try ConnectionSessionAcquisitionPIDRequestRecord(
                    request: request,
                    sessionID: sessionKey,
                    batchOrdinal: batch.identity.ordinal
                ).insert(database)
            }
        }
    }

    /// 保存処理の失敗をチャンク保存の失敗理由へ変換します。
    ///
    /// 責務: 分類済みの失敗はそのまま、範囲外・制約違反は整合性エラー、それ以外は保存先利用不可へ分類します。
    /// - Parameter error: 検証、Record変換、またはGRDBが送出した失敗。
    /// - Returns: 呼び出し側へ返す失敗理由。
    private func translatedError(_ error: any Error) -> ConnectionSessionAcquisitionChunkRepositoryError {
        if let error = error as? ConnectionSessionAcquisitionChunkRepositoryError {
            return error
        }
        if let error = error as? ConnectionSessionRepositoryError, error == .integrityConflict {
            return .integrityConflict
        }
        if let error = error as? DatabaseError, error.resultCode == .SQLITE_CONSTRAINT {
            return .integrityConflict
        }
        logger.error("取得チャンク保存失敗: \(String(describing: error), privacy: .private)")
        return .unavailable
    }
}
