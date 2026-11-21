import Foundation

/// 規制の形状の種類(JARTIC の点・線・面コード)です。
nonisolated enum RoadRegulationShape: Int, Sendable {
    /// 点(1)。
    case point = 1
    /// 線(2)。
    case line = 2
    /// 面(3)。
    case area = 3
}
