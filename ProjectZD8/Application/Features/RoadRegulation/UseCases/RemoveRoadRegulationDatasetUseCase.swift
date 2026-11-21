import Foundation

/// 1県の交通規制データを削除するユースケースです。
///
/// 有効な版を引退させて検索の対象から外してから、引退済みの版を掃除します。
/// 掃除の失敗は削除の失敗にしません(引退で削除は済んでおり、残りは次の掃除で消えます)。
nonisolated struct RemoveRoadRegulationDatasetUseCase: Sendable {
    /// 版の保存先。
    private let datasets: any RoadRegulationDatasetRepository
    /// 失敗の分類。
    private let classifier = RoadRegulationImportErrorClassifier()

    /// 保存先を受け取ります。
    ///
    /// 責務: 版の保存先を保持します。
    /// - Parameter datasets: 版の保存先。
    init(datasets: any RoadRegulationDatasetRepository) {
        self.datasets = datasets
    }

    /// 県の有効な版を削除します。
    ///
    /// 責務: メインスレッドの外で、引退と掃除を順に行います。有効な版が無ければ何もしません。
    /// - Parameter prefecture: 削除する県。
    /// - Throws: 引退の失敗を分類した取り込みのエラー。
    @concurrent
    func execute(prefecture: JapanesePrefectureCode) async throws {
        do {
            _ = try datasets.retireActiveDataset(for: prefecture)
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
        try? datasets.purgeInactiveDatasets()
    }
}
