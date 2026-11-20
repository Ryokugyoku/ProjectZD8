import Foundation

/// 有効な交通規制データの版を、都道府県の昇順で読むユースケースです。
nonisolated struct ListRoadRegulationDatasetsUseCase: Sendable {
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

    /// 有効な版を読みます。
    ///
    /// 責務: 保存先から有効な版を読み、失敗を取り込みのエラーに分類します(空の一覧に潰しません)。
    /// - Returns: 有効な版(都道府県の昇順)。
    /// - Throws: `storageUnavailable` などの取り込みのエラー。
    func execute() throws -> [RoadRegulationDataset] {
        do {
            return try datasets.activeDatasets()
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
    }
}
