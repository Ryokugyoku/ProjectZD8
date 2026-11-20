import Foundation

/// 規制の条件(対象1〜5と除外1〜5)が、ある時刻(日本時間)の本人の車に当てはまるかを3値で判定します。
///
/// 全体の式は「いずれかの対象 i が当てはまり、かつ対応する除外 i が当てはまらない」で、クリーネの3値論理で組み合わせます。
/// 空の対象 i は使いません。対象がすべて空なら常に対象とし、空でない除外だけを当てます。
nonisolated struct RoadRegulationApplicabilityEvaluator: Sendable {
    /// 期間の規則。
    private let periodRule = RegulationPeriodRule()
    /// 時間帯の規則。
    private let timeWindowRule = RegulationTimeWindowRule()
    /// 曜日の規則。
    private let dayRule = RegulationDayRule()
    /// 車両コードの規則。
    private let vehicleRule: RegulationVehicleCodeRule

    /// 本人の車の種類から判定を作ります。
    ///
    /// 責務: 車両コードの規則を車の種類に合わせて用意します。
    /// - Parameter vehicleClass: 本人の車の種類。既定は普通乗用車。
    init(vehicleClass: RegulationVehicleClass = .standardPassenger) {
        vehicleRule = RegulationVehicleCodeRule(vehicleClass: vehicleClass)
    }

    /// 条件が指定の時刻に当てはまるかを返します。
    ///
    /// 責務: 空でない対象 i ごとに「対象 i かつ 除外 i でない」を求めて論理和を取ります。対象がすべて空なら除外だけを当てます。
    /// - Parameters:
    ///   - conditions: 規制の条件。
    ///   - date: 走行の時刻(実時間)。
    /// - Returns: 3値の判定。
    func evaluate(_ conditions: RoadRegulationConditions, at date: Date) -> RegulationApplicability {
        let pairs = zip(conditions.targets, conditions.exclusions)
        let usedPairs = pairs.filter { !$0.0.isEmpty }
        guard !usedPairs.isEmpty else {
            return conditions.exclusions.reduce(.applies) { $0.and(notExcluded(by: $1, at: date)) }
        }
        return usedPairs.reduce(.doesNotApply) { result, pair in
            result.or(evaluateTarget(pair.0, at: date).and(notExcluded(by: pair.1, at: date)))
        }
    }

    /// 対象の1組が当てはまるかを返します。
    ///
    /// 責務: 期間・時間帯と曜日・車両の3つを論理積で組み合わせます。
    /// - Parameters:
    ///   - set: 対象の1組。
    ///   - date: 走行の時刻。
    /// - Returns: 3値の判定。
    private func evaluateTarget(_ set: RoadRegulationConditionSet, at date: Date) -> RegulationApplicability {
        evaluateSchedule(set, at: date).and(vehicleRule.evaluateTarget(set))
    }

    /// 除外の1組に当てはまらない(除外されない)かを返します。
    ///
    /// 責務: 空の除外は「除外しない」とし、それ以外は期間・時間帯と曜日・車両の論理積を否定します。
    /// - Parameters:
    ///   - set: 除外の1組。
    ///   - date: 走行の時刻。
    /// - Returns: 除外されなければ `applies`、除外されれば `doesNotApply`。
    private func notExcluded(by set: RoadRegulationConditionSet, at date: Date) -> RegulationApplicability {
        guard !set.isEmpty else { return .applies }
        return evaluateSchedule(set, at: date).and(vehicleRule.evaluateExclusion(set)).negated
    }

    /// 1組の期間と時間帯・曜日が当てはまるかを返します。
    ///
    /// 責務: 期間の規則と、時間帯と曜日の規則を論理積で組み合わせます。
    /// - Parameters:
    ///   - set: 1組。
    ///   - date: 走行の時刻。
    /// - Returns: 3値の判定。
    private func evaluateSchedule(_ set: RoadRegulationConditionSet, at date: Date) -> RegulationApplicability {
        let period = periodRule.evaluate(start: set.periodStart, end: set.periodEnd, at: date)
        let window = timeWindowRule.evaluate(start: set.timeStart, end: set.timeEnd, dayCode: set.dayCode, at: date, dayRule: dayRule)
        return period.and(window)
    }
}
