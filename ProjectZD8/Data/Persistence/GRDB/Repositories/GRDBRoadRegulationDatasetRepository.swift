import Foundation
import GRDB

/// GRDB/SQLiteへ交通規制データの版を保存し、取り込み・有効化・削除を扱います。
///
/// 取り込みは「新しい版を `importing` で作る → 規制を小分けに入れる → 1トランザクションで有効な版を入れ替える」の順です。
/// 途中で失敗・中断しても、それまで有効だった版が残ります。
nonisolated final class GRDBRoadRegulationDatasetRepository: RoadRegulationDatasetRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBRoadRegulationErrorTranslator()
    /// 規制と升目の一括挿入です。
    private let inserter = GRDBRoadRegulationBatchInserter()
    /// 版の小分けの削除です。
    private let purger: GRDBRoadRegulationDatasetPurger

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を交通規制スキーマ利用可能状態へ移行し、削除の小分けの件数を決めます。
    /// - Parameters:
    ///   - databaseQueue: 交通規制データを保存するDB Queue。
    ///   - purgeBatchSize: 削除で1回に消す規制の行数(1未満は1とみなす)。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue, purgeBatchSize: Int = 2_000) throws {
        self.databaseQueue = databaseQueue
        purger = GRDBRoadRegulationDatasetPurger(batchSize: purgeBatchSize)
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// 有効な版を返します。
    ///
    /// 責務: 1回の読取transactionで `active` の版と拒否件数を読み、都道府県コードの昇順で復元します。
    /// - Returns: 有効な版。無ければ空配列。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func activeDatasets() throws -> [RoadRegulationDataset] {
        try translatingErrors {
            try databaseQueue.read { database in
                let records = try RoadRegulationDatasetRecord
                    .filter(Column("state") == RoadRegulationDatasetState.active.rawValue)
                    .order(Column("prefectureCode"))
                    .fetchAll(database)
                return try records.map { try makeDataset(from: $0, in: database) }
            }
        }
    }

    /// 新しい版の取り込みを始めます。
    ///
    /// 責務: 新しい識別子で `importing` の版の行を作ります。同じ県に取り込み中の版があれば一意制約で拒否されます。
    /// - Parameter draft: 取り込み前に分かっている版の情報。
    /// - Returns: 作った版の識別子。
    /// - Throws: 制約違反は `.integrityConflict`、SQLITE_FULL は `.storageFull`、それ以外は `.unavailable`。
    func beginImport(_ draft: RoadRegulationDatasetDraft) throws -> RoadRegulationDatasetID {
        try translatingErrors {
            let datasetID = RoadRegulationDatasetID(rawValue: UUID())
            let record = try RoadRegulationDatasetRecord(id: datasetID, draft: draft)
            try databaseQueue.write { try record.insert($0) }
            return datasetID
        }
    }

    /// 取り込み中の版へ規制をまとめて書きます。
    ///
    /// 責務: 1つの書込みtransactionで規制と升目の索引を挿入し、ユニークキーが重複した行は挿入しません。
    /// - Parameters:
    ///   - batch: 書く規制と升目。
    ///   - datasetID: 書き込む版。
    /// - Returns: 実際に挿入した件数(重複キーは数えない)。
    /// - Throws: 版が無ければ `.notFound`、取り込み中でない・制約違反は `.integrityConflict`、SQLITE_FULL は `.storageFull`。
    func appendRegulations(_ batch: [RoadRegulationIndexedDraft], to datasetID: RoadRegulationDatasetID) throws -> Int {
        try translatingErrors {
            try databaseQueue.write { try inserter.insert(batch, into: datasetID, in: $0) }
        }
    }

    /// 取り込みを終えた版を有効にします。
    ///
    /// 責務: 1つの書込みtransactionで、同じ県の旧 `active` を `retired` にし、結果と拒否件数を書いてこの版を `active` にします。
    /// - Parameters:
    ///   - datasetID: 有効にする版。
    ///   - summary: 取り込みの結果。
    ///   - activatedAt: 有効にした時刻。
    /// - Returns: 有効にした版。
    /// - Throws: 版が無ければ `.notFound`、取り込み中でない・制約違反は `.integrityConflict`、それ以外は `.unavailable`。
    func activate(
        _ datasetID: RoadRegulationDatasetID,
        summary: RoadRegulationImportSummary,
        activatedAt: Date
    ) throws -> RoadRegulationDataset {
        try translatingErrors {
            try databaseQueue.write { database in
                try activate(datasetID, summary: summary, activatedAt: activatedAt, in: database)
            }
        }
    }

    /// 版を捨てます。
    ///
    /// 責務: 有効な版なら先に検索から外し、升目・規制・版の行を小分けのtransactionで削除します。
    /// - Parameter datasetID: 捨てる版。
    /// - Throws: 版が無ければ `.notFound`、それ以外は `.unavailable` など。
    func discard(_ datasetID: RoadRegulationDatasetID) throws {
        try translatingErrors {
            try purger.purge(datasetID.rawValue.uuidString.lowercased(), in: databaseQueue)
        }
    }

    /// 都道府県の有効な版を引退させます。
    ///
    /// 責務: 1つの書込みtransactionで `active` の版を `retired` にし、検索の対象から外します。
    /// - Parameter prefecture: 対象の都道府県。
    /// - Returns: 引退させた版があれば `true`。
    /// - Throws: 書込み失敗は `.unavailable` など。
    func retireActiveDataset(for prefecture: JapanesePrefectureCode) throws -> Bool {
        try translatingErrors {
            try databaseQueue.write { database in
                try retireActive(prefectureCode: prefecture.rawValue, in: database)
                return database.changesCount > 0
            }
        }
    }

    /// 有効でない版を掃除します。
    ///
    /// 責務: `retired` と `importing` の版を1件ずつ小分けに削除します。取り込み中に呼んではいけません。
    /// - Throws: 読取・削除の失敗は `.unavailable` など。
    func purgeInactiveDatasets() throws {
        try translatingErrors {
            let inactiveStates = [RoadRegulationDatasetState.retired.rawValue, RoadRegulationDatasetState.importing.rawValue]
            let keys = try databaseQueue.read { database in
                try String.fetchAll(
                    database,
                    RoadRegulationDatasetRecord
                        .select(Column("id"))
                        .filter(inactiveStates.contains(Column("state")))
                )
            }
            for key in keys {
                try purger.purge(key, in: databaseQueue)
            }
        }
    }

    /// 書込みtransactionの中で版を有効にします。
    ///
    /// 責務: 版の状態を確かめ、旧 `active` を引退させ、結果と拒否件数を書いて復元した版を返します。
    /// - Parameters:
    ///   - datasetID: 有効にする版。
    ///   - summary: 取り込みの結果。
    ///   - activatedAt: 有効にした時刻。
    ///   - database: 書込みtransaction中の接続。
    /// - Returns: 有効にした版。
    /// - Throws: 版が無ければ `.notFound`、取り込み中でなければ `.integrityConflict`、それ以外は GRDB の失敗。
    private func activate(
        _ datasetID: RoadRegulationDatasetID,
        summary: RoadRegulationImportSummary,
        activatedAt: Date,
        in database: Database
    ) throws -> RoadRegulationDataset {
        let key = datasetID.rawValue.uuidString.lowercased()
        guard let current = try RoadRegulationDatasetRecord.fetchOne(database, key: key) else {
            throw RoadRegulationRepositoryError.notFound
        }
        guard current.state == RoadRegulationDatasetState.importing.rawValue else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
        try retireActive(prefectureCode: Int(current.prefectureCode), in: database)
        let activated = try current.activated(with: summary, at: activatedAt)
        try activated.update(database)
        try RoadRegulationDatasetRejectionRecord.filter(Column("datasetID") == key).deleteAll(database)
        let rejections = RoadRegulationDatasetRejectionRecord.records(for: summary.counts.rejectedByReason, datasetID: datasetID)
        for rejection in rejections {
            try rejection.insert(database)
        }
        return try activated.makeDomainDataset(rejections: rejections)
    }

    /// 県の有効な版を引退させる文を実行します。
    ///
    /// 責務: 同じ県の `active` の行を `retired` にします。変更件数は `database.changesCount` で読めます。
    /// - Parameters:
    ///   - prefectureCode: 対象の都道府県コード。
    ///   - database: 書込みtransaction中の接続。
    /// - Throws: GRDB の失敗。
    private func retireActive(prefectureCode: Int, in database: Database) throws {
        try database.execute(
            sql: """
                UPDATE \(RoadRegulationDatasetRecord.databaseTableName) SET state = ?
                WHERE prefectureCode = ? AND state = ?
                """,
            arguments: [
                RoadRegulationDatasetState.retired.rawValue,
                prefectureCode,
                RoadRegulationDatasetState.active.rawValue,
            ]
        )
    }

    /// 版の行と拒否件数の行から Domain の版を復元します。
    ///
    /// 責務: 版の拒否件数を読み、版の行と合わせて復元します。
    /// - Parameters:
    ///   - record: 版の行。
    ///   - database: 読取中の接続。
    /// - Returns: 復元した版。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外は GRDB の失敗。
    private func makeDataset(from record: RoadRegulationDatasetRecord, in database: Database) throws -> RoadRegulationDataset {
        let rejections = try RoadRegulationDatasetRejectionRecord
            .filter(Column("datasetID") == record.id)
            .fetchAll(database)
        return try record.makeDomainDataset(rejections: rejections)
    }

    /// 処理の失敗を Repository の失敗理由へ変換します。
    ///
    /// 責務: 成功はそのまま返し、失敗は `RoadRegulationRepositoryError` にして投げ直します。
    /// - Parameter body: 実行する処理。
    /// - Returns: 処理の結果。
    /// - Throws: `RoadRegulationRepositoryError`。
    private func translatingErrors<Value>(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }
}
