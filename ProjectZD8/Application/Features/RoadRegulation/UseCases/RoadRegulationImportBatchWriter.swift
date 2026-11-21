import Foundation

/// アーカイブから読んだ記録を受け取り、升目を付けて、一定件数ごとに取り込み中の版へ書き込む型です。
///
/// - 規制は `RoadRegulationGrid` で升目を求めます。升目へ割り当てられない(上限を超える)形状は `geometryTooLarge` として数えます。
/// - `batchSize` 件たまるたびに、1回の `appendRegulations` で書きます。書く前に取り消しを確かめます。
/// - 挿入されなかった件数(ユニークキーの重複)は `duplicateUniqueKey` として数えます。
/// - 読み飛ばしと破棄は理由ごとに数え、黙って消しません。
/// - 版の範囲は、升目を付けられた全規制の外接矩形の和です。
nonisolated struct RoadRegulationImportBatchWriter {
    /// 書き込む先の、取り込み中の版。
    private let datasetID: RoadRegulationDatasetID
    /// 書き込むリポジトリ。
    private let repository: any RoadRegulationDatasetRepository
    /// 升目の計算。
    private let grid: RoadRegulationGrid
    /// 1回に書く件数(1以上)。
    private let batchSize: Int
    /// まだ書いていない規制。
    private var pending: [RoadRegulationIndexedDraft] = []
    /// 挿入できた件数。
    private(set) var importedCount = 0
    /// 対象外の種別で読み飛ばした件数。
    private var skippedOutOfScope = 0
    /// 廃止済みで読み飛ばした件数。
    private var skippedAbolished = 0
    /// 理由ごとの破棄の件数。
    private var rejectedByReason: [RoadRegulationRowRejection: Int] = [:]
    /// 升目を付けた規制の外接矩形の和。
    private var coverage: GeoBoundingBox?

    /// 書き込む先と書き込みの単位を決めます。
    ///
    /// 責務: 書き込みの設定を保持します(1未満の件数は1にします)。
    /// - Parameters:
    ///   - datasetID: 書き込む先の、取り込み中の版。
    ///   - repository: 書き込むリポジトリ。
    ///   - grid: 升目の計算。
    ///   - batchSize: 1回に書く件数。
    init(datasetID: RoadRegulationDatasetID, repository: any RoadRegulationDatasetRepository, grid: RoadRegulationGrid, batchSize: Int) {
        self.datasetID = datasetID
        self.repository = repository
        self.grid = grid
        self.batchSize = max(1, batchSize)
        pending.reserveCapacity(self.batchSize)
    }

    /// 1件の記録を受け取ります。
    ///
    /// 責務: 規制なら升目を付けて溜め(件数に達したら書き)、読み飛ばしと破棄は理由ごとに数えます。
    /// - Parameter record: アーカイブから読んだ1件。
    /// - Throws: 書き込みの失敗(リポジトリのエラー)と `CancellationError`。
    mutating func accept(_ record: RoadRegulationArchiveRecord) throws {
        switch record {
        case let .regulation(draft):
            try accept(draft)
        case .skipped(.outOfScopeKind):
            skippedOutOfScope += 1
        case .skipped(.abolished):
            skippedAbolished += 1
        case let .rejected(reason):
            reject(reason)
        }
    }

    /// 残りを書き、件数と範囲をまとめます。
    ///
    /// 責務: 溜まっている規制を書き、取り込みの件数と版の範囲を返します。
    /// - Parameter totalRows: CSV のデータ行の数。
    /// - Returns: 件数と、範囲(規制が1件も無ければ `nil`)。
    /// - Throws: 書き込みの失敗と `CancellationError`。
    mutating func finish(totalRows: Int) throws -> (counts: RoadRegulationImportCounts, coverage: GeoBoundingBox?) {
        try flush()
        let counts = RoadRegulationImportCounts(
            totalRows: totalRows,
            importedRegulations: importedCount,
            skippedOutOfScope: skippedOutOfScope,
            skippedAbolished: skippedAbolished,
            rejectedByReason: rejectedByReason
        )
        return (counts, coverage)
    }

    /// 1件の規制に升目を付けて溜めます。
    ///
    /// 責務: 升目の計算と範囲の更新を行い、件数に達したら書きます。
    /// - Parameter draft: 保存前の規制。
    /// - Throws: 書き込みの失敗と `CancellationError`。
    private mutating func accept(_ draft: RoadRegulationDraft) throws {
        guard let cells = grid.cells(covering: draft.geometry, shape: draft.kind.expectedShape) else {
            reject(.geometryTooLarge)
            return
        }
        pending.append(RoadRegulationIndexedDraft(draft: draft, cells: cells))
        if let box = draft.geometry.boundingBox {
            coverage = coverage.map { $0.union(box) } ?? box
        }
        if pending.count >= batchSize {
            try flush()
        }
    }

    /// 溜まっている規制を1回で書きます。
    ///
    /// 責務: 取り消しを確かめてから書き、挿入できた件数と重複の件数を数えます。
    /// - Throws: 書き込みの失敗と `CancellationError`。
    private mutating func flush() throws {
        guard !pending.isEmpty else { return }
        try Task.checkCancellation()
        let inserted = try repository.appendRegulations(pending, to: datasetID)
        let duplicates = pending.count - inserted
        importedCount += inserted
        if duplicates > 0 {
            rejectedByReason[.duplicateUniqueKey, default: 0] += duplicates
        }
        pending.removeAll(keepingCapacity: true)
    }

    /// 破棄を理由ごとに数えます。
    ///
    /// 責務: 理由の件数を1つ増やします。
    /// - Parameter reason: 破棄の理由。
    private mutating func reject(_ reason: RoadRegulationRowRejection) {
        rejectedByReason[reason, default: 0] += 1
    }
}
