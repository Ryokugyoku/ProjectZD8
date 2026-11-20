/// 走行ルートを描けた時に添える注記です。
nonisolated enum DrivingRouteNotice: Equatable, Sendable {
    /// 途中で記録できなかった区間があります。理由は記録中以外の事象由来の7つだけです。
    case partiallyRecorded(DrivingRouteAbsenceReason)
    /// 概略の位置で記録した区間があります。
    case reducedAccuracy
    /// 精度の低い位置を除きました。
    case inaccurateFixesExcluded
    /// 以前に復元した写しで、最新かを確かめられていません。
    case unverifiedRestoredCopy
}
