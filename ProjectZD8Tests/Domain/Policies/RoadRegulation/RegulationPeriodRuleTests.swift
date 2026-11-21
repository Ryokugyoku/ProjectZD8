import XCTest
@testable import ProjectZD8

/// `RegulationPeriodRule` が、規制期間(MMDD)を両端を含めて日本時間で判定することを検証します。
final class RegulationPeriodRuleTests: XCTestCase {
    private let rule = RegulationPeriodRule()

    /// 責務: 月日と時刻を指定して判定します。
    private func evaluate(_ start: String?, _ end: String?, month: Int, day: Int, year: Int = 2026, hour: Int = 12) -> RegulationApplicability {
        rule.evaluate(start: start, end: end, at: RoadRegulationTokyoClock.date(year, month, day, hour))
    }

    /// 責務: 期間が未記入なら年間を通じて適用になることを確かめます。
    func testMissingPeriodAlwaysApplies() {
        XCTAssertEqual(evaluate(nil, nil, month: 6, day: 15), .applies)
    }

    /// 責務: 年をまたがない期間(401〜930)の両端が含まれ、その外が含まれないことを確かめます。
    func testSameYearPeriodIsInclusiveAtBothEnds() {
        XCTAssertEqual(evaluate("401", "930", month: 4, day: 1), .applies)
        XCTAssertEqual(evaluate("401", "930", month: 9, day: 30, hour: 23), .applies)
        XCTAssertEqual(evaluate("401", "930", month: 6, day: 15), .applies)
        XCTAssertEqual(evaluate("401", "930", month: 3, day: 31, hour: 23), .doesNotApply)
        XCTAssertEqual(evaluate("401", "930", month: 10, day: 1, hour: 0), .doesNotApply)
    }

    /// 責務: 年をまたぐ期間(1201〜228)の内側と外側と、両端を確かめます。
    func testPeriodCrossingNewYear() {
        XCTAssertEqual(evaluate("1201", "228", month: 1, day: 15), .applies)
        XCTAssertEqual(evaluate("1201", "228", month: 12, day: 1), .applies)
        XCTAssertEqual(evaluate("1201", "228", month: 12, day: 31), .applies)
        XCTAssertEqual(evaluate("1201", "228", month: 2, day: 28, hour: 23), .applies)
        XCTAssertEqual(evaluate("1201", "228", month: 3, day: 1), .doesNotApply)
        XCTAssertEqual(evaluate("1201", "228", month: 11, day: 30, hour: 23), .doesNotApply)
        XCTAssertEqual(evaluate("1201", "228", month: 7, day: 1), .doesNotApply)
    }

    /// 責務: 閏年の2月29日が、2月28日で終わる期間の外として扱われることを確かめます。
    func testLeapDayIsOutsidePeriodEndingFebruary28() {
        XCTAssertEqual(evaluate("1201", "228", month: 2, day: 29, year: 2028), .doesNotApply)
        XCTAssertEqual(evaluate("1201", "229", month: 2, day: 29, year: 2028), .applies)
    }

    /// 責務: 1日だけの期間(開始と終了が同じ)がその日だけに当てはまることを確かめます。
    func testSingleDayPeriod() {
        XCTAssertEqual(evaluate("505", "505", month: 5, day: 5), .applies)
        XCTAssertEqual(evaluate("505", "505", month: 5, day: 4, hour: 23), .doesNotApply)
        XCTAssertEqual(evaluate("505", "505", month: 5, day: 6, hour: 0), .doesNotApply)
    }

    /// 責務: 不正な月日(月13・日32・存在しない日・数字以外)が不明になることを確かめます。
    func testMalformedPeriodsAreUnknown() {
        XCTAssertEqual(evaluate("1340", "228", month: 1, day: 15), .unknown)
        XCTAssertEqual(evaluate("101", "1340", month: 1, day: 15), .unknown)
        XCTAssertEqual(evaluate("132", "228", month: 1, day: 15), .unknown)
        XCTAssertEqual(evaluate("abc", "228", month: 1, day: 15), .unknown)
        XCTAssertEqual(evaluate("0", "228", month: 1, day: 15), .unknown)
    }

    /// 責務: 開始と終了の片方だけの記入が不明になることを確かめます。
    func testHalfFilledPeriodIsUnknown() {
        XCTAssertEqual(evaluate("401", nil, month: 5, day: 1), .unknown)
        XCTAssertEqual(evaluate(nil, "930", month: 5, day: 1), .unknown)
    }

    /// 責務: 3〜4桁の数字だけが通り、その月にあり得ない日(2月30日・4月31日)や桁違いが不明になることを確かめます。
    func testDigitCountAndDayOfMonthValidity() {
        XCTAssertEqual(evaluate("230", "301", month: 2, day: 10), .unknown)
        XCTAssertEqual(evaluate("101", "431", month: 2, day: 10), .unknown)
        XCTAssertEqual(evaluate("1", "930", month: 2, day: 10), .unknown)
        XCTAssertEqual(evaluate("01010", "930", month: 2, day: 10), .unknown)
        XCTAssertEqual(evaluate("0101", "0930", month: 2, day: 10), .applies)
        XCTAssertEqual(evaluate("１０１", "930", month: 2, day: 10), .unknown)
    }

    /// 責務: 日本時間の日付で判定する(協定世界時では前日の 1月 1日 00:30 も1月1日)ことを確かめます。
    func testDateIsInterpretedInTokyo() {
        XCTAssertEqual(evaluate("101", "101", month: 1, day: 1, hour: 0), .applies)
        XCTAssertEqual(evaluate("1231", "1231", month: 1, day: 1, hour: 0), .doesNotApply)
    }
}
