import Foundation

/// 交通規制データの保存先DBを準備できない場合に、版の操作で明示的失敗を返します。
nonisolated struct UnavailableRoadRegulationDatasetRepository: RoadRegulationDatasetRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 有効な版の読取を利用不能エラーへ変換し、版なしとして扱いません。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func activeDatasets() throws -> [RoadRegulationDataset] {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 取り込みの開始を利用不能エラーへ変換します。
    /// - Parameter draft: 使用しない版の情報。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func beginImport(_ draft: RoadRegulationDatasetDraft) throws -> RoadRegulationDatasetID {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 規制の書込みを利用不能エラーへ変換し、0件の成功として扱いません。
    /// - Parameters:
    ///   - batch: 使用しない規制。
    ///   - datasetID: 使用しない版。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func appendRegulations(_ batch: [RoadRegulationIndexedDraft], to datasetID: RoadRegulationDatasetID) throws -> Int {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 版の有効化を利用不能エラーへ変換します。
    /// - Parameters:
    ///   - datasetID: 使用しない版。
    ///   - summary: 使用しない結果。
    ///   - activatedAt: 使用しない時刻。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func activate(
        _ datasetID: RoadRegulationDatasetID,
        summary: RoadRegulationImportSummary,
        activatedAt: Date
    ) throws -> RoadRegulationDataset {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に削除失敗を通知します。
    ///
    /// 責務: 版の削除を利用不能エラーへ変換し、成功として扱いません。
    /// - Parameter datasetID: 使用しない版。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func discard(_ datasetID: RoadRegulationDatasetID) throws {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に保存失敗を通知します。
    ///
    /// 責務: 有効な版の引退を利用不能エラーへ変換し、版なし(false)として扱いません。
    /// - Parameter prefecture: 使用しない都道府県。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func retireActiveDataset(for prefecture: JapanesePrefectureCode) throws -> Bool {
        throw RoadRegulationRepositoryError.unavailable
    }

    /// 常に削除失敗を通知します。
    ///
    /// 責務: 掃除を利用不能エラーへ変換し、成功として扱いません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func purgeInactiveDatasets() throws {
        throw RoadRegulationRepositoryError.unavailable
    }
}
