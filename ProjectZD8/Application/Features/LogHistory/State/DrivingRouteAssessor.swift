/// 軌跡の事象と区切った走行ルートから、描けない理由と添える注記を判定します。
///
/// 規則(上から順に適用):
/// 1. ルートに点がある: 理由なし。注記は「部分(優先度の最も高い理由)→ 概略 → 除外」の順。
/// 2. 点が無く、サンプルがある(すべて除外): `allFixesInaccurate`。
/// 3. 点もサンプルも無く、記録中以外の事象がある: 優先度の最も高い事象の理由。
/// 4. 記録中の事象しか無い: `noFixesReceived`。
/// 5. 何も無い: `notRecorded`。
nonisolated struct DrivingRouteAssessor: Sendable {
    /// 理由の優先度(先頭ほど高い)です。利用者の操作で直せる根本の原因を先に出します。
    private static let reasonPriority: [DrivingRouteAbsenceReason] = [
        .unsupportedPlatform,
        .disabledBySetting,
        .authorizationRestricted,
        .authorizationDenied,
        .authorizationNotDetermined,
        .backgroundWithoutAlwaysAuthorization,
        .locationUnavailable
    ]

    /// 除外の注記を出す「除外数 ÷ 全点数」の下限(ちょうどを含む)です。
    private let excludedNoticeRatio: Double

    /// 除外の注記を出す割合を固定して生成します。
    ///
    /// 責務: 判定に使うしきい値を保持します。
    /// - Parameter excludedNoticeRatio: 除外の注記を出す割合の下限(既定は 10%)。
    init(excludedNoticeRatio: Double = 0.1) {
        self.excludedNoticeRatio = excludedNoticeRatio
    }

    /// 軌跡と走行ルートから、描けない理由と注記を判定します。
    ///
    /// 責務: 点の有無・サンプルの有無・事象の種類から規則1〜5のどれかを選びます。
    /// - Parameters:
    ///   - track: 元の軌跡(サンプルと事象)。
    ///   - route: 軌跡を区切った走行ルート。
    /// - Returns: 理由(点がある時は `nil`)と表示順の注記。
    func assess(track: ConnectionSessionLocationTrack, route: DrivingRoute) -> DrivingRouteAssessment {
        let eventReason = Self.highestPriorityReason(in: track.events)
        if route.firstPoint != nil {
            return DrivingRouteAssessment(absenceReason: nil, notices: notices(track: track, route: route, eventReason: eventReason))
        }
        return DrivingRouteAssessment(absenceReason: absenceReason(track: track, eventReason: eventReason), notices: [])
    }

    /// 点がある時に添える注記を並べます。
    ///
    /// 責務: 部分・概略・除外の注記を、条件を満たすものだけ表示順に並べます。
    /// - Parameters:
    ///   - track: 元の軌跡。
    ///   - route: 区切った走行ルート。
    ///   - eventReason: 記録中以外の事象のうち優先度の最も高い理由。
    /// - Returns: 表示順の注記。
    private func notices(
        track: ConnectionSessionLocationTrack,
        route: DrivingRoute,
        eventReason: DrivingRouteAbsenceReason?
    ) -> [DrivingRouteNotice] {
        var notices: [DrivingRouteNotice] = []
        if let eventReason {
            notices.append(.partiallyRecorded(eventReason))
        }
        if Self.hasReducedAccuracy(track: track, route: route) {
            notices.append(.reducedAccuracy)
        }
        if hasManyExcludedFixes(route) {
            notices.append(.inaccurateFixesExcluded)
        }
        return notices
    }

    /// 点が無い時の理由を選びます。
    ///
    /// 責務: サンプルの有無と事象から規則2〜5の理由を選びます。
    /// - Parameters:
    ///   - track: 元の軌跡。
    ///   - eventReason: 記録中以外の事象のうち優先度の最も高い理由。
    /// - Returns: 描けない理由。
    private func absenceReason(
        track: ConnectionSessionLocationTrack,
        eventReason: DrivingRouteAbsenceReason?
    ) -> DrivingRouteAbsenceReason {
        if !track.samples.isEmpty {
            return .allFixesInaccurate
        }
        if let eventReason {
            return eventReason
        }
        return track.events.isEmpty ? .notRecorded : .noFixesReceived
    }

    /// 除外した点の割合が注記を出すほど多いかを返します。
    ///
    /// 責務: 全点数が正の時だけ「除外数 ÷ 全点数 ≥ しきい値」を判定します。
    /// - Parameter route: 区切った走行ルート。
    /// - Returns: 注記を出すなら `true`。
    private func hasManyExcludedFixes(_ route: DrivingRoute) -> Bool {
        guard route.totalFixCount > 0 else {
            return false
        }
        return Double(route.excludedFixCount) / Double(route.totalFixCount) >= excludedNoticeRatio
    }

    /// 概略の位置で記録した部分があるかを返します。
    ///
    /// 責務: 概略の記録の事象か、概略の区間のどちらかがあれば真とします。
    /// - Parameters:
    ///   - track: 元の軌跡。
    ///   - route: 区切った走行ルート。
    /// - Returns: 概略の部分があれば `true`。
    private static func hasReducedAccuracy(track: ConnectionSessionLocationTrack, route: DrivingRoute) -> Bool {
        track.events.contains { $0.kind == .recordingWithReducedAccuracy }
            || route.segments.contains { $0.precision == .approximate }
    }

    /// 記録中以外の事象のうち、優先度の最も高い理由を返します。
    ///
    /// 責務: 事象を理由へ写し、優先度の表で最も前にあるものを選びます。
    /// - Parameter events: 軌跡の事象。
    /// - Returns: 記録中以外の事象が無ければ `nil`。
    private static func highestPriorityReason(in events: [ConnectionSessionLocationEvent]) -> DrivingRouteAbsenceReason? {
        let reasons = Set(events.compactMap { reason(for: $0.kind) })
        return reasonPriority.first { reasons.contains($0) }
    }

    /// 事象の種類を描けない理由へ写します。
    ///
    /// 責務: 記録中の2種を除く7種を、同じ意味の理由へ対応付けます。
    /// - Parameter kind: 事象の種類。
    /// - Returns: 記録中の事象なら `nil`。
    private static func reason(for kind: ConnectionSessionLocationEventKind) -> DrivingRouteAbsenceReason? {
        switch kind {
        case .recording, .recordingWithReducedAccuracy: nil
        case .disabledBySetting: .disabledBySetting
        case .authorizationNotDetermined: .authorizationNotDetermined
        case .authorizationDenied: .authorizationDenied
        case .authorizationRestricted: .authorizationRestricted
        case .backgroundWithoutAlwaysAuthorization: .backgroundWithoutAlwaysAuthorization
        case .locationUnavailable: .locationUnavailable
        case .unsupportedPlatform: .unsupportedPlatform
        }
    }
}
