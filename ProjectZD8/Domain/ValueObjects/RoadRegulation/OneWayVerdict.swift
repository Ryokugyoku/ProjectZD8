import Foundation

/// 一方通行の区間の判定です(文言を持ちません)。
nonisolated enum OneWayVerdict: Equatable, Sendable {
    /// 通行できる向きに進んだ。
    case followedDirection
    /// 逆向きに進んだ可能性がある(逆向きに進んだ距離)。
    case possibleWrongWay(distanceMeters: Double)
    /// 判定できない。
    case undeterminable(RoadRegulationUndeterminedReason)
}
