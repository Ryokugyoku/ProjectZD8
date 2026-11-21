import Foundation

/// matcher の1歩の結果です。
nonisolated struct RoadRegulationMatchStep: Equatable, Sendable {
    /// 次の点へ持ち越す状態。
    let state: RoadRegulationMatchState
    /// いま乗っている規制。
    let position: RoadRegulationPosition
    /// この点で起きた変化(起きた順)。
    let changes: [RoadRegulationChange]
}
