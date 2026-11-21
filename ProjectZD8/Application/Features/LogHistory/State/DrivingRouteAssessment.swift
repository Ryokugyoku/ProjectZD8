/// 軌跡と区切った走行ルートから判定した、描けない理由と注記です。
nonisolated struct DrivingRouteAssessment: Equatable, Sendable {
    /// 描けない理由です。描ける点がある時は `nil` です。
    let absenceReason: DrivingRouteAbsenceReason?
    /// 表示順に並んだ注記です。
    let notices: [DrivingRouteNotice]
}
