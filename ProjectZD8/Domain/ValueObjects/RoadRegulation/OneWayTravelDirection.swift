import Foundation

/// 一方通行の区間を進む向きです。
nonisolated enum OneWayTravelDirection: String, Sendable {
    /// 通行できる向き。
    case permitted
    /// 通行できる向きと逆。
    case reverse
}
