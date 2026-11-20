import Foundation

/// 規制の形状を構成する区間の役割です。`rawValue` は形状 BLOB の役割バイトに固定されています。
nonisolated enum RoadRegulationGeometryRole: UInt8, Sendable, CaseIterable {
    /// 規制場所そのもの(点・線・面)。
    case main = 0
    /// 一時停止の進入方向の点。
    case approach = 1
    /// 除外区間・区域。
    case exclusion = 2
}
