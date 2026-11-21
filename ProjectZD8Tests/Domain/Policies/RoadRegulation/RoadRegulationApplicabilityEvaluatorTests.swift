import XCTest
@testable import ProjectZD8

/// `RoadRegulationApplicabilityEvaluator` が、対象 i と除外 i の組をクリーネの3値論理で合成することを検証します。
final class RoadRegulationApplicabilityEvaluatorTests: XCTestCase {
    private let evaluator = RoadRegulationApplicabilityEvaluator()

    /// 責務: 時間帯と車両コードを指定した条件の組を作ります。
    private func set(
        time: (String, String)? = nil,
        day: String? = nil,
        period: (String, String)? = nil,
        a: String? = nil,
        d: String? = nil
    ) -> RoadRegulationConditionSet {
        RoadRegulationConditionSet(
            periodStart: period?.0,
            periodEnd: period?.1,
            timeStart: time?.0,
            timeEnd: time?.1,
            dayCode: day,
            vehicleCodeA: a,
            vehicleCodeD: d
        )
    }

    /// 責務: 対象と除外のリストから条件を作ります。
    private func conditions(_ targets: [RoadRegulationConditionSet], _ exclusions: [RoadRegulationConditionSet] = []) -> RoadRegulationConditions {
        RoadRegulationConditions(targets: targets, exclusions: exclusions)
    }

    /// 責務: 条件が無ければ常に適用になることを確かめます。
    func testUnconditionalAlwaysApplies() {
        XCTAssertEqual(evaluator.evaluate(.unconditional, at: RoadRegulationTokyoClock.wednesday()), .applies)
        XCTAssertEqual(evaluator.evaluate(conditions([.empty, .empty]), at: RoadRegulationTokyoClock.sunday(3, 0)), .applies)
    }

    /// 責務: 時間「700〜900」の組が、時刻ごとに3値の結果を返すことを確かめます。
    func testSingleTimeWindowTarget() {
        let target = conditions([set(time: ("700", "900"))])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(8, 59)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(9, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions([set(time: ("abc", "900"))]), at: RoadRegulationTokyoClock.wednesday(8, 0)), .unknown)
    }

    /// 責務: 対象が2組(7〜9時と15〜17時)なら、どちらかに入れば適用になることを確かめます。
    func testTwoTargetsAreCombinedWithOr() {
        let target = conditions([set(time: ("700", "900")), set(time: ("1500", "1700"))])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(16, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(8, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(12, 0)), .doesNotApply)
    }

    /// 責務: 対象の組のうち、不明が1つあれば、他が当てはまれば適用・当てはまらなければ不明になることを確かめます。
    func testUnknownTargetInOr() {
        let target = conditions([set(time: ("abc", "900")), set(time: ("1500", "1700"))])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(16, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(12, 0)), .unknown)
    }

    /// 責務: 空の対象の組は使われず、その除外の有無にも影響されないことを確かめます。
    func testEmptyTargetSetsAreIgnored() {
        let target = conditions([.empty, set(time: ("1500", "1700")), .empty])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(12, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(15, 30)), .applies)
    }

    /// 責務: 日付をまたぐ時間帯と曜日の組(土曜 23:00〜05:00)が、日本時間の日時で判定されることを確かめます。
    func testCrossingMidnightWithDayCode() {
        let target = conditions([set(time: ("2300", "500"), day: "4")])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.saturday(23, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.sunday(3, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.saturday(3, 0)), .doesNotApply)
    }

    /// 責務: 期間と時間帯と車両が、1つの組の中で AND で合成されることを確かめます。
    func testFieldsInOneSetAreCombinedWithAnd() {
        let target = conditions([set(time: ("700", "900"), period: ("1101", "1130"), a: "1")])
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(8, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.date(2026, 12, 2, 8, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.wednesday(10, 0)), .doesNotApply)
        let kei = conditions([set(a: "1000000000")])
        XCTAssertEqual(evaluator.evaluate(kei, at: RoadRegulationTokyoClock.wednesday()), .doesNotApply)
        XCTAssertEqual(RoadRegulationApplicabilityEvaluator(vehicleClass: .keiPassenger).evaluate(kei, at: RoadRegulationTokyoClock.wednesday()), .applies)
    }

    /// 責務: 対象車両の判定(普乗・その他・解釈できない値)が全体の結果へ反映されることを確かめます。
    func testVehicleCodesInTargets() {
        let date = RoadRegulationTokyoClock.wednesday()
        XCTAssertEqual(evaluator.evaluate(conditions([set(a: "1")]), at: date), .applies)
        XCTAssertEqual(evaluator.evaluate(conditions([set(d: "1000")]), at: date), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions([set(d: "100000000000000")]), at: date), .unknown)
        XCTAssertEqual(evaluator.evaluate(conditions([set(a: "1", d: "100000000000000")]), at: date), .applies)
        XCTAssertEqual(evaluator.evaluate(conditions([set(a: "2")]), at: date), .unknown)
    }

    /// 責務: 除外の車両が当てはまれば適用されず、除外の「その他」だけなら除外しないことを確かめます。
    func testExclusionByVehicle() {
        let date = RoadRegulationTokyoClock.wednesday()
        XCTAssertEqual(evaluator.evaluate(conditions([set(a: "1")], [set(a: "1000")]), at: date), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions([set(a: "1")], [set(d: "100000000000000")]), at: date), .applies)
    }

    /// 責務: 除外の曜日が不明(曜日2の水曜)なら全体も不明、確定する日(日曜)なら除外されることを確かめます。
    func testExclusionByDayCode() {
        let targets = [set(a: "1")]
        let exclusions = [set(day: "2")]
        XCTAssertEqual(evaluator.evaluate(conditions(targets, exclusions), at: RoadRegulationTokyoClock.wednesday()), .unknown)
        XCTAssertEqual(evaluator.evaluate(conditions(targets, exclusions), at: RoadRegulationTokyoClock.sunday()), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions(targets, [set(day: "1")]), at: RoadRegulationTokyoClock.wednesday()), .applies)
    }

    /// 責務: 除外に時間帯だけがある時は、車両の制約なしとして、その時間帯だけ除外することを確かめます。
    func testExclusionTimeWindowExcludesOnlyInsideIt() {
        let conditions = conditions([set(a: "1")], [set(time: ("700", "900"))])
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.wednesday(8, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.wednesday(10, 0)), .applies)
    }

    /// 責務: 除外 i が対応する対象 i にだけ作用し、別の対象 j には作用しないことを確かめます。
    func testExclusionAppliesOnlyToCorrespondingTarget() {
        let conditions = conditions(
            [set(time: ("700", "900")), set(time: ("1500", "1700"))],
            [set(day: "1"), .empty]
        )
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.saturday(8, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.saturday(16, 0)), .applies)
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.wednesday(8, 0)), .applies)
    }

    /// 責務: 対象がすべて空で除外だけに値がある時、常に対象として、空でない除外だけを当てることを確かめます。
    func testAllTargetsEmptyWithExclusionsOnly() {
        let onlyExclusion = conditions([], [set(time: ("700", "900"))])
        XCTAssertEqual(evaluator.evaluate(onlyExclusion, at: RoadRegulationTokyoClock.wednesday(8, 0)), .doesNotApply)
        XCTAssertEqual(evaluator.evaluate(onlyExclusion, at: RoadRegulationTokyoClock.wednesday(10, 0)), .applies)
        let unknownExclusion = conditions([], [set(day: "2"), .empty])
        XCTAssertEqual(evaluator.evaluate(unknownExclusion, at: RoadRegulationTokyoClock.wednesday()), .unknown)
        XCTAssertEqual(evaluator.evaluate(unknownExclusion, at: RoadRegulationTokyoClock.sunday()), .doesNotApply)
    }

    /// 責務: 対象 i が空の時、対応する除外 i は使われない(別の対象が使われている場合)ことを確かめます。
    func testExclusionOfEmptyTargetIsNotUsed() {
        let conditions = conditions([.empty, set(time: ("700", "900"))], [set(day: "1"), .empty])
        XCTAssertEqual(evaluator.evaluate(conditions, at: RoadRegulationTokyoClock.saturday(8, 0)), .applies)
    }

    /// 責務: 時間の片方だけの記入が全体でも不明になることを確かめます。
    func testHalfFilledTimeIsUnknown() {
        let date = RoadRegulationTokyoClock.wednesday(8, 0)
        XCTAssertEqual(evaluator.evaluate(conditions([set(time: ("700", ""))]), at: date), .unknown)
        XCTAssertEqual(evaluator.evaluate(conditions([RoadRegulationConditionSet(timeEnd: "900")]), at: date), .unknown)
        XCTAssertEqual(evaluator.evaluate(conditions([RoadRegulationConditionSet(periodStart: "101")]), at: date), .unknown)
    }

    /// 責務: 端末のタイムゾーンを変えても同じ結果になることを確かめます(UTC では前日になる時刻を含む)。
    func testResultIsIndependentOfDeviceTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let target = conditions([set(time: ("2300", "500"), day: "4")])
        let sundayEarly = RoadRegulationTokyoClock.sunday(3, 0)
        for identifier in ["America/New_York", "UTC", "Asia/Kolkata"] {
            NSTimeZone.default = TimeZone(identifier: identifier) ?? original
            XCTAssertEqual(evaluator.evaluate(target, at: sundayEarly), .applies, identifier)
            XCTAssertEqual(evaluator.evaluate(target, at: RoadRegulationTokyoClock.saturday(3, 0)), .doesNotApply, identifier)
        }
    }
}
