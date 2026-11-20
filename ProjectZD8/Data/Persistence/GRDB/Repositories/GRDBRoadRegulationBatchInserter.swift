import Foundation
import GRDB

/// 取り込み中の版へ、規制と升目の索引の行をまとめて挿入します。
///
/// 呼び出し側が開いた1つの書込みトランザクションの中で使います。
nonisolated struct GRDBRoadRegulationBatchInserter: Sendable {
    /// 規制の行を挿入する文です。版の中でユニークキーが重複した行だけを挿入しません。
    private static let insertRegulationSQL = """
        INSERT INTO road_regulations
            (datasetID, uniqueKey, kind, speedLimitKph, sideCode, oneWayOrder, perimeterRoadIncluded, conditions, geometry)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(datasetID, uniqueKey) DO NOTHING
        """
    /// 升目の索引の行を挿入する文です。同じ升目の重複は1行にまとめます。
    private static let insertCellSQL = """
        INSERT INTO road_regulation_cells (datasetID, cellKey, regulationID) VALUES (?, ?, ?)
        ON CONFLICT(datasetID, cellKey, regulationID) DO NOTHING
        """

    /// 形状の符号化です。
    private let codec = RoadRegulationGeometryBlobCodec()

    /// 規制と升目をまとめて挿入します。
    ///
    /// 責務: 版が取り込み中であることを確かめ、規制ごとに行を挿入し、挿入できた規制にだけ升目の行を付けます。
    /// - Parameters:
    ///   - batch: 書く規制と升目。
    ///   - datasetID: 書き込む版。
    ///   - database: 書込みトランザクション中の接続。
    /// - Returns: 実際に挿入した規制の件数(重複キーは数えない)。
    /// - Throws: 版が無ければ `.notFound`、取り込み中でなければ `.integrityConflict`、それ以外は GRDB の失敗。
    func insert(
        _ batch: [RoadRegulationIndexedDraft],
        into datasetID: RoadRegulationDatasetID,
        in database: Database
    ) throws -> Int {
        let datasetKey = datasetID.rawValue.uuidString.lowercased()
        try requireImporting(datasetKey, in: database)
        let regulationStatement = try database.cachedStatement(sql: Self.insertRegulationSQL)
        let cellStatement = try database.cachedStatement(sql: Self.insertCellSQL)
        var insertedCount = 0
        for item in batch {
            let record = try RoadRegulationRecord(draft: item.draft, datasetID: datasetID, codec: codec)
            try regulationStatement.execute(arguments: record.insertionArguments)
            guard database.changesCount > 0 else { continue }
            insertedCount += 1
            let regulationID = database.lastInsertedRowID
            for cell in item.cells {
                try cellStatement.execute(arguments: [datasetKey, cell.rawValue, regulationID])
            }
        }
        return insertedCount
    }

    /// 版が取り込み中であることを確かめます。
    ///
    /// 責務: 版の状態を読み、無い・取り込み中でない場合に投げます。
    /// - Parameters:
    ///   - datasetKey: 版のUUIDの小文字の文字列。
    ///   - database: 接続。
    /// - Throws: 版が無ければ `.notFound`、取り込み中でなければ `.integrityConflict`。
    private func requireImporting(_ datasetKey: String, in database: Database) throws {
        let state = try String.fetchOne(
            database,
            sql: "SELECT state FROM \(RoadRegulationDatasetRecord.databaseTableName) WHERE id = ?",
            arguments: [datasetKey]
        )
        guard let state else { throw RoadRegulationRepositoryError.notFound }
        guard state == RoadRegulationDatasetState.importing.rawValue else {
            throw RoadRegulationRepositoryError.integrityConflict
        }
    }
}
