import Foundation
import GRDB

/// GRDB/SQLiteから、升目の key の集合に掛かる有効な版の交通規制を引きます。
nonisolated final class GRDBRoadRegulationQueryRepository: RoadRegulationQueryRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// 1回の問い合わせに渡す升目の最大数です。
    private let cellsPerQuery: Int
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBRoadRegulationErrorTranslator()
    /// 形状の復号です。
    private let codec = RoadRegulationGeometryBlobCodec()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を交通規制スキーマ利用可能状態へ移行し、問い合わせの分け方を決めます。
    /// - Parameters:
    ///   - databaseQueue: 交通規制データを保存するDB Queue。
    ///   - cellsPerQuery: 1回の問い合わせに渡す升目の最大数(1未満は1とみなす)。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue, cellsPerQuery: Int = 500) throws {
        self.databaseQueue = databaseQueue
        self.cellsPerQuery = max(1, cellsPerQuery)
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// 升目に掛かる規制を返します。
    ///
    /// 責務: 升目を `cellsPerQuery` 件ずつに分けて1回の読取transactionで問い合わせ、`active` の版の規制だけを
    /// 行 ID の昇順・重複なしで復元します。取り込み中・引退した版の規制は返しません。
    /// - Parameter cells: 調べる升目。
    /// - Returns: 行 ID の昇順・重複なしの規制。升目が空なら空配列。
    /// - Throws: 復元不能は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func regulations(inCells cells: Set<RoadRegulationCellKey>) throws -> [RoadRegulation] {
        guard !cells.isEmpty else { return [] }
        let chunks = chunked(cells.map(\.rawValue).sorted())
        do {
            let recordsByID = try databaseQueue.read { database in
                var recordsByID: [Int64: RoadRegulationRecord] = [:]
                for chunk in chunks {
                    try merge(fetchRecords(cellKeys: chunk, in: database), into: &recordsByID)
                }
                return recordsByID
            }
            return try recordsByID
                .sorted { $0.key < $1.key }
                .map { try $0.value.makeDomainRegulation(codec: codec) }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 升目の key を問い合わせの単位に分けます。
    ///
    /// 責務: 並んだ key を `cellsPerQuery` 件ずつの配列にします。
    /// - Parameter keys: 升目の key。
    /// - Returns: 分けた key の配列。
    private func chunked(_ keys: [Int64]) -> [[Int64]] {
        stride(from: 0, to: keys.count, by: cellsPerQuery).map { start in
            Array(keys[start..<min(start + cellsPerQuery, keys.count)])
        }
    }

    /// 読んだ行を行 ID ごとにまとめます。
    ///
    /// 責務: 複数回の問い合わせで重なった規制を行 ID で1件にします。行 ID の無い行は整合性エラーにします。
    /// - Parameters:
    ///   - records: 読んだ行。
    ///   - recordsByID: まとめ先。
    /// - Throws: 行 ID の無い行は `RoadRegulationRepositoryError.integrityConflict`。
    private func merge(_ records: [RoadRegulationRecord], into recordsByID: inout [Int64: RoadRegulationRecord]) throws {
        for record in records {
            guard let id = record.id else { throw RoadRegulationRepositoryError.integrityConflict }
            recordsByID[id] = record
        }
    }

    /// 1回分の升目に掛かる有効な版の規制の行を読みます。
    ///
    /// 責務: `active` の版の升目の索引から規制の行 ID を集め、同じく `active` の版に属する規制の行を返します。
    /// - Parameters:
    ///   - cellKeys: 升目の key(1件以上)。
    ///   - database: 読取中の接続。
    /// - Returns: 規制の行(順不同)。
    /// - Throws: GRDB の失敗。
    private func fetchRecords(cellKeys: [Int64], in database: Database) throws -> [RoadRegulationRecord] {
        let placeholders = Array(repeating: "?", count: cellKeys.count).joined(separator: ", ")
        let active = RoadRegulationDatasetState.active.rawValue
        let sql = """
            SELECT * FROM road_regulations
            WHERE id IN (
                SELECT c.regulationID FROM road_regulation_datasets AS d
                JOIN road_regulation_cells AS c ON c.datasetID = d.id
                WHERE d.state = '\(active)' AND c.cellKey IN (\(placeholders))
            )
            AND datasetID IN (SELECT id FROM road_regulation_datasets WHERE state = '\(active)')
            """
        return try RoadRegulationRecord.fetchAll(database, sql: sql, arguments: StatementArguments(cellKeys))
    }
}
