import XCTest
@testable import ProjectZD8

/// `RegulationTimeWindowRule` が、規制時間(hhmm)と曜日を日本時間で3値に判定することを検証します。
final class RegulationTimeWindowRuleTests: XCTestCase {
    private let rule = RegulationTimeWindowRule()

    /// 責務: 時間帯と曜日コードを指定して判定します。
    private func evaluate(_ start: String?, _ end: String?, day: String? = nil, at date: Date) -> RegulationApplicability {
        rule.evaluate(start: start, end: end, dayCode: day, at: date, dayRule: RegulationDayRule())
    }

    /// 責務: 700〜900 が [開始, 終了) として、開始ちょうどは含み、終了ちょうどは含まないことを確かめます。
    func testSameDayWindowIncludesStartAndExcludesEnd() {
        let wednesday = RoadRegulationTokyoClock.wednesday
        XCTAssertEqual(evaluate("700", "900", at: wednesday(8, 59)), .applies)
        XCTAssertEqual(evaluate("700", "900", at: wednesday(9, 0)), .doesNotApply)
        XCTAssertEqual(evaluate("700", "900", at: wednesday(7, 0)), .applies)
        XCTAssertEqual(evaluate("700", "900", at: wednesday(6, 59)), .doesNotApply)
    }

    /// 責務: 0〜2400 と、開始と終了が同じ時間帯が終日として扱われることを確かめます。
    func testAllDayWindows() {
        let wednesday = RoadRegulationTokyoClock.wednesday
        XCTAssertEqual(evaluate("0", "2400", at: wednesday(23, 59)), .applies)
        XCTAssertEqual(evaluate("0", "2400", at: wednesday(0, 0)), .applies)
        XCTAssertEqual(evaluate("900", "900", at: wednesday(3, 0)), .applies)
        XCTAssertEqual(evaluate("900", "900", at: wednesday(15, 0)), .applies)
    }

    /// 責務: 2200〜400 の日付をまたぐ時間帯の、前後と境界を確かめます。
    func testWindowCrossingMidnight() {
        let wednesday = RoadRegulationTokyoClock.wednesday
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(23, 0)), .applies)
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(3, 59)), .applies)
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(4, 0)), .doesNotApply)
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(21, 59)), .doesNotApply)
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(22, 0)), .applies)
        XCTAssertEqual(evaluate("2200", "400", at: wednesday(0, 0)), .applies)
    }

    /// 責務: 日付をまたぐ時間帯の曜日が開始時点の曜日で判定される(土曜 23:00〜日曜 05:00)ことを確かめます。
    func testCrossingMidnightUsesStartDayForDayCode() {
        XCTAssertEqual(evaluate("2300", "500", day: "4", at: RoadRegulationTokyoClock.saturday(23, 0)), .applies)
        XCTAssertEqual(evaluate("2300", "500", day: "4", at: RoadRegulationTokyoClock.sunday(3, 0)), .applies)
        XCTAssertEqual(evaluate("2300", "500", day: "4", at: RoadRegulationTokyoClock.saturday(3, 0)), .doesNotApply)
        XCTAssertEqual(evaluate("2300", "500", day: "4", at: RoadRegulationTokyoClock.sunday(23, 0)), .doesNotApply)
    }

    /// 責務: 時間が解釈できない値(分が60以上・2400超・数字以外)が不明になることを確かめます。
    func testMalformedTimesAreUnknown() {
        let date = RoadRegulationTokyoClock.wednesday(8, 0)
        XCTAssertEqual(evaluate("760", "900", at: date), .unknown)
        XCTAssertEqual(evaluate("700", "960", at: date), .unknown)
        XCTAssertEqual(evaluate("700", "2500", at: date), .unknown)
        XCTAssertEqual(evaluate("abc", "900", at: date), .unknown)
        XCTAssertEqual(evaluate("700", "xyz", at: date), .unknown)
        XCTAssertEqual(evaluate("0", "2401", at: date), .unknown)
    }

    /// 責務: 時間が未記入なら、曜日だけで決まる(曜日も無ければ適用)ことを確かめます。
    func testMissingTimesFallBackToDayCodeOnly() {
        XCTAssertEqual(evaluate(nil, nil, at: RoadRegulationTokyoClock.wednesday()), .applies)
        XCTAssertEqual(evaluate(nil, nil, day: "4", at: RoadRegulationTokyoClock.saturday()), .applies)
        XCTAssertEqual(evaluate(nil, nil, day: "4", at: RoadRegulationTokyoClock.wednesday()), .doesNotApply)
        XCTAssertEqual(evaluate(nil, nil, day: "2", at: RoadRegulationTokyoClock.wednesday()), .unknown)
    }

    /// 責務: 開始と終了の片方だけがある時間が不明になることを確かめます。
    func testHalfFilledTimeIsUnknown() {
        let date = RoadRegulationTokyoClock.wednesday(8, 0)
        XCTAssertEqual(evaluate("700", nil, at: date), .unknown)
        XCTAssertEqual(evaluate(nil, "900", at: date), .unknown)
        XCTAssertEqual(evaluate(nil, "900", day: "1", at: RoadRegulationTokyoClock.saturday(8, 0)), .unknown)
    }

    /// 責務: 休日(コード6)は、日付をまたぐ時間帯でも曜日に関係なく不明になることを確かめます。
    func testHolidayCodeIsAlwaysUnknown() {
        XCTAssertEqual(evaluate("2300", "500", day: "6", at: RoadRegulationTokyoClock.saturday(23, 30)), .unknown)
        XCTAssertEqual(evaluate("700", "900", day: "6", at: RoadRegulationTokyoClock.wednesday(8, 0)), .unknown)
    }

    /// 責務: 時間帯の中でも、曜日が合わなければ当てはまらず、曜日が不明なら不明になることを確かめます。
    func testDayCodeCombinesWithTimeWindow() {
        XCTAssertEqual(evaluate("700", "900", day: "1", at: RoadRegulationTokyoClock.saturday(8, 0)), .applies)
        XCTAssertEqual(evaluate("700", "900", day: "1", at: RoadRegulationTokyoClock.wednesday(8, 0)), .doesNotApply)
        XCTAssertEqual(evaluate("700", "900", day: "2", at: RoadRegulationTokyoClock.wednesday(8, 0)), .unknown)
        XCTAssertEqual(evaluate("700", "900", day: "2", at: RoadRegulationTokyoClock.wednesday(10, 0)), .doesNotApply)
        XCTAssertEqual(evaluate("700", "900", day: "99", at: RoadRegulationTokyoClock.saturday(8, 0)), .unknown)
    }

    /// 責務: 日本時間では日中でも協定世界時では前日になる時刻を、日本時間で判定することを確かめます。
    func testTimeIsInterpretedInTokyoNotUTC() {
        let saturdayEarlyMorning = RoadRegulationTokyoClock.saturday(1, 0)
        XCTAssertEqual(evaluate("0", "300", at: saturdayEarlyMorning), .applies)
        XCTAssertEqual(evaluate("1600", "1700", at: saturdayEarlyMorning), .doesNotApply)
        XCTAssertEqual(evaluate("700", "900", day: "4", at: RoadRegulationTokyoClock.saturday(8, 0)), .applies)
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles") ?? original
        XCTAssertEqual(evaluate("0", "300", at: saturdayEarlyMorning), .applies)
        XCTAssertEqual(evaluate("2200", "400", day: "4", at: saturdayEarlyMorning), .doesNotApply)
    }
}
