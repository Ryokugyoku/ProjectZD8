import Foundation

/// 一時停止の規制と、その進入方向の1つを識別します。
nonisolated struct StopApproachKey: Hashable, Sendable {
    /// 一時停止の規制。
    let regulationID: RoadRegulationID
    /// 進入方向の点の位置(`RoadRegulationGeometry.approachPoints` の添字)。
    let approachIndex: Int
}
