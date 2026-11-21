import Foundation

/// 以前の取り込みで残った版(取り込み中・引退済み)と一時 ZIP を消すユースケースです。
///
/// 取り込みの途中に呼んではいけません(取り込み中の版を消してしまうため。呼び出し側が守ります)。
nonisolated struct PurgeRoadRegulationLeftoversUseCase: Sendable {
    /// 版の保存先。
    private let datasets: any RoadRegulationDatasetRepository
    /// 一時 ZIP の取得元。
    private let source: any RoadRegulationSourcePort
    /// 失敗の分類。
    private let classifier = RoadRegulationImportErrorClassifier()

    /// 保存先と取得元を受け取ります。
    ///
    /// 責務: 掃除の対象を保持します。
    /// - Parameters:
    ///   - datasets: 版の保存先。
    ///   - source: 一時 ZIP の取得元。
    init(datasets: any RoadRegulationDatasetRepository, source: any RoadRegulationSourcePort) {
        self.datasets = datasets
        self.source = source
    }

    /// 残った版と一時 ZIP を消します。
    ///
    /// 責務: メインスレッドの外で、一時 ZIP と有効でない版を消します。
    /// - Throws: 版の掃除の失敗を分類した取り込みのエラー。
    @concurrent
    func execute() async throws {
        source.removeLeftoverDownloads()
        do {
            try datasets.purgeInactiveDatasets()
        } catch {
            throw classifier.classified(error, fallback: .storageUnavailable)
        }
    }
}
