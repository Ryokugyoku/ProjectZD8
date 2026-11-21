import Foundation

/// 一方通行の座標の並び方(JARTIC の指定・禁止方向の別コード)です。
nonisolated enum RoadRegulationOneWayOrder: Int, Codable, Sendable {
    /// 禁止する向きの順に座標が並ぶ(1)。
    case prohibitedDirection = 1
    /// 通行できる向きの順に座標が並ぶ(2)。
    case permittedDirection = 2
}
