import Foundation
import GRDB

/// GRDB/SQLiteへ走行ルートの同期記録を保存し、アップロード候補と復元を扱います。
nonisolated final class GRDBConnectionSessionLocationTrackSyncRepository: ConnectionSessionLocationTrackSyncRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBConnectionSessionSegmentationErrorTranslator()
    /// アップロード候補の問合せです。
    private let candidateQuery = GRDBConnectionSessionLocationTrackCandidateQuery()
    /// 復元による置き換えです。
    private let restorer = GRDBConnectionSessionLocationTrackRestorer()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を同期記録スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 同期記録を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// アップロード候補を返します。
    ///
    /// 責務: 終了済み・アカウント一致・点か事象あり・同期記録なしか uploaded のセッションを水位つきで返します。
    /// - Parameter accountIdentifier: 対象のアカウント識別子。
    /// - Returns: 候補の一覧。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func uploadCandidates(for accountIdentifier: String) throws -> [ConnectionSessionLocationTrackUploadCandidate] {
        do {
            return try databaseQueue.read { try candidateQuery.candidates(for: accountIdentifier, in: $0) }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの軌跡を返します。
    ///
    /// 責務: 1回の読取transactionでサンプルと事象を読み、行が無ければ空の軌跡を返します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: 軌跡。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func track(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrack {
        do {
            let key = sessionID.rawValue.uuidString.lowercased()
            return try databaseQueue.read { database in
                let samples = try ConnectionSessionLocationSampleRecord
                    .filter(Column("sessionID") == key).order(Column("sequence")).fetchAll(database)
                    .map { try $0.makeDomainSample() }
                let events = try ConnectionSessionLocationEventRecord
                    .filter(Column("sessionID") == key).order(Column("eventOrdinal")).fetchAll(database)
                    .map { try $0.makeDomainEvent() }
                return ConnectionSessionLocationTrack(sessionID: sessionID, samples: samples, events: events)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの同期記録を返します。
    ///
    /// 責務: 1件の同期記録を読み、無ければ nil を返します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: 同期記録。無ければ nil。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func syncRecord(for sessionID: ConnectionSessionID) throws -> ConnectionSessionLocationTrackSyncRecord? {
        do {
            let key = sessionID.rawValue.uuidString.lowercased()
            return try databaseQueue.read { database in
                try ConnectionSessionLocationTrackSyncStateRecord.fetchOne(database, key: key)?.makeDomainRecord()
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 送信済みとして同期記録を保存します。
    ///
    /// 責務: origin = uploaded で同期記録を上書き保存します。restored の行がある場合は拒否します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - manifestDigest: 送信したAssetバイト列のSHA-256。
    ///   - watermark: 送信した時点の水位。
    ///   - date: 同期した時刻。
    /// - Throws: セッション不在・restored の行・制約違反は `.integrityConflict`、それ以外は `.unavailable`。
    func markUploaded(
        sessionID: ConnectionSessionID,
        manifestDigest: String,
        watermark: ConnectionSessionLocationTrackWatermark,
        at date: Date
    ) throws {
        do {
            let key = sessionID.rawValue.uuidString.lowercased()
            let record = try ConnectionSessionLocationTrackSyncStateRecord(
                ConnectionSessionLocationTrackSyncRecord(
                    sessionID: sessionID,
                    origin: .uploaded,
                    manifestDigest: manifestDigest,
                    watermark: watermark,
                    syncedAt: date
                )
            )
            try databaseQueue.write { database in
                let exists = try ConnectionSessionRecord.filter(Column("id") == key).fetchCount(database) > 0
                let existing = try ConnectionSessionLocationTrackSyncStateRecord.fetchOne(database, key: key)
                guard exists, existing?.origin != ConnectionSessionLocationTrackSyncOrigin.restored.rawValue else {
                    throw ConnectionSessionRepositoryError.integrityConflict
                }
                try record.save(database)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// iCloudから取得した軌跡でローカルの軌跡を置き換えます。
    ///
    /// 責務: 1つの書込みtransactionで軌跡行を入れ直し、origin = restored の同期記録を保存します。途中で失敗したら全体を巻き戻します。
    /// - Parameters:
    ///   - verified: digest照合済みの軌跡。
    ///   - date: 同期した時刻。
    /// - Throws: セッション不在・この端末で記録した行がある・制約違反は `.integrityConflict`、それ以外は `.unavailable`。
    func replaceWithRestoredTrack(_ verified: VerifiedConnectionSessionLocationTrack, at date: Date) throws {
        do {
            try databaseQueue.write { try restorer.replace(verified, at: date, in: $0) }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }
}
