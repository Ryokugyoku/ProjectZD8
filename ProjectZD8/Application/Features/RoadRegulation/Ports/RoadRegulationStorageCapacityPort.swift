import Foundation

/// 端末の空き容量を調べる能力です。
nonisolated protocol RoadRegulationStorageCapacityPort: Sendable {
    /// 使える空き容量を返します。
    ///
    /// 責務: 交通規制データの保存先がある領域の空き容量を調べます。
    /// - Returns: 空き容量(バイト)。
    /// - Throws: 調べられなければその失敗。
    func availableCapacityBytes() throws -> Int64
}
