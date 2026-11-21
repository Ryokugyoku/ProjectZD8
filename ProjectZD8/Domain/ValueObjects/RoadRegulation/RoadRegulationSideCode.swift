import Foundation

/// 規制が道路の片側か両側か(JARTIC の片側・両側コード)です。
nonisolated enum RoadRegulationSideCode: Int, Codable, Sendable {
    /// 該当なし(1)。
    case none = 1
    /// 片側(2)。
    case oneSide = 2
    /// 両側(3)。
    case bothSides = 3
}
