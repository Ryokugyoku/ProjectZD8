import Foundation

/// RoadRegulation の判定の報告(Domain)を、Analysis の照合結果(`SessionRoadRegulationReview`)へ写します。
///
/// Analysis が RoadRegulation の具象型に依存しないよう、App 層に置きます。
/// - 1つの判定を1つの項目にし、報告の各配列の順のまま(最高速度 → 一時停止 → 一方通行 → 徐行)並べます。
/// - 集計(tally)は使いません。件数は Analysis 側で項目から数え直します。
/// - 文言キーは `RoadRegulationVerdictTextKeys` が返すものをそのまま使います(判定できない時は理由のキー)。
nonisolated struct RoadRegulationSessionReviewMapper: Sendable {
    /// 判定の分類と数値です(項目を作る途中の値)。
    private struct Classification {
        /// 照合の結果の分類。
        let outcome: SessionRoadRegulationReviewOutcome
        /// 判定できない理由(判定できない時だけ非 nil)。
        let reason: RoadRegulationUndeterminedReason?
        /// 表示する数値。
        let figures: SessionRoadRegulationReviewFigures
    }

    /// 判定の文言キーを選ぶ部品です。
    private let textKeys: RoadRegulationVerdictTextKeys

    /// 文言キーの部品を固定して生成します。
    ///
    /// 責務: 判定の文言キーを選ぶ部品を保持します。
    /// - Parameter textKeys: 判定の文言キーを選ぶ部品。
    init(textKeys: RoadRegulationVerdictTextKeys = .init()) {
        self.textKeys = textKeys
    }

    /// 判定の報告を照合結果へ写します。
    ///
    /// 責務: 4種類の判定を項目へ写し、車速の有無と使った版を範囲から、利用日と配布ページを引数から入れます。
    /// - Parameters:
    ///   - report: 判定の報告。
    ///   - usedOn: 使った版の取得日時の最大(無ければ nil)。
    ///   - sourceURL: 配布ページ。
    /// - Returns: 照合結果。
    func review(from report: SessionRoadRegulationReport, usedOn: Date?, sourceURL: URL) -> SessionRoadRegulationReview {
        SessionRoadRegulationReview(
            entries: entries(from: report),
            hasVehicleSpeed: report.coverage.hasVehicleSpeed,
            datasets: report.coverage.datasets,
            usedOn: usedOn,
            sourceURL: sourceURL
        )
    }

    /// 報告の4つの配列を、順を保って項目の並びにします。
    ///
    /// 責務: 最高速度 → 一時停止 → 一方通行 → 徐行の順に、各配列の順のまま項目へ写します。
    /// - Parameter report: 判定の報告。
    /// - Returns: 項目の並び。
    private func entries(from report: SessionRoadRegulationReport) -> [SessionRoadRegulationReviewEntry] {
        report.speedLimit.map(speedLimitEntry)
            + report.stops.map(stopEntry)
            + report.oneWay.map(oneWayEntry)
            + report.slowDown.map(slowDownEntry)
    }

    /// 最高速度の判定を項目にします。
    ///
    /// 責務: 通過の区間の始まりと終わりを印にし、判定を分類します(制限値は判定に関係なく渡します)。
    /// - Parameter judgement: 最高速度の判定。
    /// - Returns: 項目。
    private func speedLimitEntry(_ judgement: SpeedLimitJudgement) -> SessionRoadRegulationReviewEntry {
        entry(
            kind: .speedLimit,
            verdictKey: textKeys.key(for: judgement.verdict),
            classification: Self.classify(judgement.verdict, limitKph: judgement.limitKph),
            start: judgement.traversal.start,
            end: judgement.traversal.end
        )
    }

    /// 一時停止の判定を項目にします。
    ///
    /// 責務: 停止線へ近づき始めた印と着いた印を区間にし、判定を分類します。
    /// - Parameter judgement: 一時停止の判定。
    /// - Returns: 項目。
    private func stopEntry(_ judgement: StopJudgement) -> SessionRoadRegulationReviewEntry {
        entry(
            kind: .stop,
            verdictKey: textKeys.key(for: judgement.verdict),
            classification: Self.classify(judgement.verdict),
            start: judgement.passage.approachStarted,
            end: judgement.passage.reached
        )
    }

    /// 一方通行の判定を項目にします。
    ///
    /// 責務: 通過の区間の始まりと終わりを印にし、判定を分類します。
    /// - Parameter judgement: 一方通行の判定。
    /// - Returns: 項目。
    private func oneWayEntry(_ judgement: OneWayJudgement) -> SessionRoadRegulationReviewEntry {
        entry(
            kind: .oneWay,
            verdictKey: textKeys.key(for: judgement.verdict),
            classification: Self.classify(judgement.verdict),
            start: judgement.traversal.start,
            end: judgement.traversal.end
        )
    }

    /// 徐行の判定を項目にします。
    ///
    /// 責務: 通過の区間の始まりと終わりを印にし、判定を分類します。
    /// - Parameter judgement: 徐行の判定。
    /// - Returns: 項目。
    private func slowDownEntry(_ judgement: SlowDownJudgement) -> SessionRoadRegulationReviewEntry {
        entry(
            kind: .slowDown,
            verdictKey: textKeys.key(for: judgement.verdict),
            classification: Self.classify(judgement.verdict),
            start: judgement.traversal.start,
            end: judgement.traversal.end
        )
    }

    /// 分類と区間の印から項目を組み立てます。
    ///
    /// 責務: 種類・文言キー・分類・区間の印を1つの項目にまとめます。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - verdictKey: 判定の文言キー。
    ///   - classification: 判定の分類と数値。
    ///   - start: 区間の始まりの印。
    ///   - end: 区間の終わりの印。
    /// - Returns: 項目。
    private func entry(
        kind: SessionRoadRegulationReviewKind,
        verdictKey: String,
        classification: Classification,
        start: RoadRegulationTransitionMark,
        end: RoadRegulationTransitionMark
    ) -> SessionRoadRegulationReviewEntry {
        SessionRoadRegulationReviewEntry(
            kind: kind,
            outcome: classification.outcome,
            verdictKey: verdictKey,
            undeterminedReason: classification.reason,
            start: start,
            end: end,
            figures: classification.figures
        )
    }

    /// 最高速度の判定を分類します。
    ///
    /// 責務: 制限内=適合、超過=確認が必要、指定なし=指定なし、判定できない=理由つきに分け、制限値と速さ・超過時間を数値にします。
    /// - Parameters:
    ///   - verdict: 最高速度の判定。
    ///   - limitKph: 判定の制限値(どの判定でも渡す)。
    /// - Returns: 分類と数値。
    private static func classify(_ verdict: SpeedLimitVerdict, limitKph: Int?) -> Classification {
        switch verdict {
        case .withinLimit(let maxKph):
            Classification(outcome: .compliant, reason: nil, figures: .init(limitKph: limitKph, maximumKph: maxKph))
        case .exceeded(let maxKph, let exceededSeconds):
            Classification(
                outcome: .possibleIssue,
                reason: nil,
                figures: .init(limitKph: limitKph, maximumKph: maxKph, exceededSeconds: exceededSeconds)
            )
        case .unregulated:
            Classification(outcome: .unregulated, reason: nil, figures: .init(limitKph: limitKph))
        case .undeterminable(let reason):
            Classification(outcome: .undeterminable, reason: reason, figures: .init(limitKph: limitKph))
        }
    }

    /// 一時停止の判定を分類します。
    ///
    /// 責務: 停止=適合、停止していない=確認が必要(最低の速さつき)、判定できない=理由つきに分けます。
    /// - Parameter verdict: 一時停止の判定。
    /// - Returns: 分類と数値。
    private static func classify(_ verdict: StopVerdict) -> Classification {
        switch verdict {
        case .stopped:
            Classification(outcome: .compliant, reason: nil, figures: .init())
        case .notStopped(let minimumKph):
            Classification(outcome: .possibleIssue, reason: nil, figures: .init(minimumKph: minimumKph))
        case .undeterminable(let reason):
            Classification(outcome: .undeterminable, reason: reason, figures: .init())
        }
    }

    /// 一方通行の判定を分類します。
    ///
    /// 責務: 向きどおり=適合、逆走の可能性=確認が必要(逆方向の距離つき)、判定できない=理由つきに分けます。
    /// - Parameter verdict: 一方通行の判定。
    /// - Returns: 分類と数値。
    private static func classify(_ verdict: OneWayVerdict) -> Classification {
        switch verdict {
        case .followedDirection:
            Classification(outcome: .compliant, reason: nil, figures: .init())
        case .possibleWrongWay(let distanceMeters):
            Classification(outcome: .possibleIssue, reason: nil, figures: .init(wrongWayDistanceMeters: distanceMeters))
        case .undeterminable(let reason):
            Classification(outcome: .undeterminable, reason: reason, figures: .init())
        }
    }

    /// 徐行の判定を分類します。
    ///
    /// 責務: 通過=数値だけを示す(最高の速さと目安つき)、判定できない=理由つきに分けます。
    /// - Parameter verdict: 徐行の判定。
    /// - Returns: 分類と数値。
    private static func classify(_ verdict: SlowDownVerdict) -> Classification {
        switch verdict {
        case .observed(let maxKph, let referenceKph):
            Classification(outcome: .observedOnly, reason: nil, figures: .init(maximumKph: maxKph, referenceKph: referenceKph))
        case .undeterminable(let reason):
            Classification(outcome: .undeterminable, reason: reason, figures: .init())
        }
    }
}
