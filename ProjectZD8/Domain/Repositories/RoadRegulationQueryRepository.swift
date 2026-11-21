import Foundation

/// 升目から交通規制を引く能力です。
///
/// 例外の約束: 保存値を復元できない場合は `RoadRegulationRepositoryError.integrityConflict`、それ以外は `.unavailable`。
nonisolated protocol RoadRegulationQueryRepository: Sendable {
    /// 升目に掛かる規制を返します。
    ///
    /// 責務: 有効な版だけから、指定した升目のどれかに索引された規制を重複なく復元します。
    /// - Parameter cells: 調べる升目。
    /// - Returns: 行 ID の昇順・重複なしの規制。
    /// - Throws: `RoadRegulationRepositoryError`。
    func regulations(inCells cells: Set<RoadRegulationCellKey>) throws -> [RoadRegulation]
}
