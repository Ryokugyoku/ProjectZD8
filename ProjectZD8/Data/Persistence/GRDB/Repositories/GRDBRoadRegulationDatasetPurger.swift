import Foundation
import GRDB

/// 交通規制データの版を、小分けの書込みトランザクションで削除します。
///
/// 1回の書込みで消す行数を抑え、共有の DB を長く占有しないようにします(記録中のセッションの書込みと分け合える)。
nonisolated struct GRDBRoadRegulationDatasetPurger: Sendable {
    /// 規制の行を1回で消す件数です。
    private let regulationBatchSize: Int
    /// 升目の行を1回で消す件数です(規制の2.5倍)。
    private let cellBatchSize: Int

    /// 1回で消す件数を決めて生成します。
    ///
    /// 責務: 規制の行の件数を1以上に揃え、升目の行の件数をその2.5倍(1以上)にします。
    /// - Parameter batchSize: 規制の行を1回で消す件数。
    init(batchSize: Int) {
        regulationBatchSize = max(1, batchSize)
        cellBatchSize = max(1, regulationBatchSize * 5 / 2)
    }

    /// 1つの版を削除します。
    ///
    /// 責務: 有効な版なら先に引退させて検索から外し、升目 → 規制の順に小分けに消し、最後に版の行を消します
    /// (拒否件数の行は版の行と連動して消えます)。
    /// - Parameters:
    ///   - datasetKey: 版のUUIDの小文字の文字列。
    ///   - databaseQueue: 書き込む DB。
    /// - Throws: 版が無ければ `RoadRegulationRepositoryError.notFound`、それ以外は GRDB の失敗。
    func purge(_ datasetKey: String, in databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { try retireIfActive(datasetKey, in: $0) }
        while try databaseQueue.write({ try deleteCellChunk(datasetKey, in: $0) }) > 0 {}
        while try databaseQueue.write({ try deleteRegulationChunk(datasetKey, in: $0) }) > 0 {}
        try databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM \(RoadRegulationDatasetRecord.databaseTableName) WHERE id = ?",
                arguments: [datasetKey]
            )
        }
    }

    /// 版の存在を確かめ、有効なら引退させます。
    ///
    /// 責務: 削除の途中の版が検索に現れないよう、`active` を `retired` にします。
    /// - Parameters:
    ///   - datasetKey: 版のUUIDの小文字の文字列。
    ///   - database: 書込みトランザクション中の接続。
    /// - Throws: 版が無ければ `RoadRegulationRepositoryError.notFound`。
    private func retireIfActive(_ datasetKey: String, in database: Database) throws {
        guard try RoadRegulationDatasetRecord.exists(database, key: datasetKey) else {
            throw RoadRegulationRepositoryError.notFound
        }
        try database.execute(
            sql: """
                UPDATE \(RoadRegulationDatasetRecord.databaseTableName) SET state = ?
                WHERE id = ? AND state = ?
                """,
            arguments: [
                RoadRegulationDatasetState.retired.rawValue,
                datasetKey,
                RoadRegulationDatasetState.active.rawValue,
            ]
        )
    }

    /// 升目の行を1回分消します。
    ///
    /// 責務: 版の升目の行を主キーの順に最大 `cellBatchSize` 件消します。
    /// - Parameters:
    ///   - datasetKey: 版のUUIDの小文字の文字列。
    ///   - database: 書込みトランザクション中の接続。
    /// - Returns: 消した行数。
    /// - Throws: GRDB の失敗。
    private func deleteCellChunk(_ datasetKey: String, in database: Database) throws -> Int {
        try database.execute(
            sql: """
                DELETE FROM road_regulation_cells
                WHERE datasetID = ? AND (cellKey, regulationID) IN (
                    SELECT cellKey, regulationID FROM road_regulation_cells WHERE datasetID = ? LIMIT ?
                )
                """,
            arguments: [datasetKey, datasetKey, cellBatchSize]
        )
        return database.changesCount
    }

    /// 規制の行を1回分消します。
    ///
    /// 責務: 版の規制の行を最大 `regulationBatchSize` 件消します。
    /// - Parameters:
    ///   - datasetKey: 版のUUIDの小文字の文字列。
    ///   - database: 書込みトランザクション中の接続。
    /// - Returns: 消した行数。
    /// - Throws: GRDB の失敗。
    private func deleteRegulationChunk(_ datasetKey: String, in database: Database) throws -> Int {
        try database.execute(
            sql: """
                DELETE FROM \(RoadRegulationRecord.databaseTableName)
                WHERE id IN (SELECT id FROM \(RoadRegulationRecord.databaseTableName) WHERE datasetID = ? LIMIT ?)
                """,
            arguments: [datasetKey, regulationBatchSize]
        )
        return database.changesCount
    }
}
