import Foundation

/// 交通規制データの保存先DBを準備できない場合に、検索で明示的失敗を返します。
nonisolated struct UnavailableRoadRegulationQueryRepository: RoadRegulationQueryRepository {
    /// 利用不能境界を生成します。
    ///
    /// 責務: 永続化不能状態を表すRepositoryを構築します。
    init() {}

    /// 常に読取失敗を通知します。
    ///
    /// 責務: 検索を利用不能エラーへ変換し、規制なしとして扱いません。
    /// - Parameter cells: 使用しない升目。
    /// - Returns: 正常終了しません。
    /// - Throws: 常に `RoadRegulationRepositoryError.unavailable`。
    func regulations(inCells cells: Set<RoadRegulationCellKey>) throws -> [RoadRegulation] {
        throw RoadRegulationRepositoryError.unavailable
    }
}
