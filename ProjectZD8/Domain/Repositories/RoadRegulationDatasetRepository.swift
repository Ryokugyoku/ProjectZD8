import Foundation

/// 交通規制データの版の取り込み・有効化・削除を行う能力です。
///
/// 例外の約束: 保存値を復元できない・制約違反は `RoadRegulationRepositoryError.integrityConflict`、
/// 保存領域の不足(SQLITE_FULL)は `.storageFull`、版の不在は `.notFound`、それ以外は `.unavailable`。
nonisolated protocol RoadRegulationDatasetRepository: Sendable {
    /// 有効な版を返します。
    ///
    /// 責務: `active` の版だけを都道府県コードの昇順で復元します。
    /// - Returns: 有効な版。無ければ空配列。
    /// - Throws: `RoadRegulationRepositoryError`。
    func activeDatasets() throws -> [RoadRegulationDataset]

    /// 新しい版の取り込みを始めます。
    ///
    /// 責務: 版の行を `importing` の状態で作ります。
    /// - Parameter draft: 取り込み前に分かっている版の情報。
    /// - Returns: 作った版の識別子。
    /// - Throws: `RoadRegulationRepositoryError`。
    func beginImport(_ draft: RoadRegulationDatasetDraft) throws -> RoadRegulationDatasetID

    /// 取り込み中の版へ規制をまとめて書きます。
    ///
    /// 責務: 1トランザクションで規制と升目の索引を挿入し、ユニークキーが重複した行は挿入しません。
    /// - Parameters:
    ///   - batch: 書く規制と升目。
    ///   - datasetID: 書き込む版。
    /// - Returns: 実際に挿入した件数(重複キーは数えない)。
    /// - Throws: `RoadRegulationRepositoryError`。
    func appendRegulations(_ batch: [RoadRegulationIndexedDraft], to datasetID: RoadRegulationDatasetID) throws -> Int

    /// 取り込みを終えた版を有効にします。
    ///
    /// 責務: 1トランザクションで同じ都道府県の旧 `active` を `retired` にし、この版を `active` にします。
    /// - Parameters:
    ///   - datasetID: 有効にする版。
    ///   - summary: 取り込みの結果。
    ///   - activatedAt: 有効にした時刻。
    /// - Returns: 有効にした版。
    /// - Throws: `RoadRegulationRepositoryError`。
    func activate(_ datasetID: RoadRegulationDatasetID, summary: RoadRegulationImportSummary, activatedAt: Date) throws -> RoadRegulationDataset

    /// 版を捨てます。
    ///
    /// 責務: 版の規制・升目・版の行を小分けのトランザクションで削除します。
    /// - Parameter datasetID: 捨てる版。
    /// - Throws: `RoadRegulationRepositoryError`。
    func discard(_ datasetID: RoadRegulationDatasetID) throws

    /// 都道府県の有効な版を引退させます。
    ///
    /// 責務: `active` の版を `retired` にし、検索の対象から外します。
    /// - Parameter prefecture: 対象の都道府県。
    /// - Returns: 引退させた版があれば `true`。
    /// - Throws: `RoadRegulationRepositoryError`。
    func retireActiveDataset(for prefecture: JapanesePrefectureCode) throws -> Bool

    /// 有効でない版を掃除します。
    ///
    /// 責務: `retired` と `importing` の版を小分けに削除します。取り込み中に呼んではいけません。
    /// - Throws: `RoadRegulationRepositoryError`。
    func purgeInactiveDatasets() throws
}
