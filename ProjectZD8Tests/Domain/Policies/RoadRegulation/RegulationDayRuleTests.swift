import XCTest
@testable import ProjectZD8

/// `RegulationDayRule` が、仕様書「曜日コード」を日本時間の曜日で3値に判定することを検証します。
final class RegulationDayRuleTests: XCTestCase {
    private let rule = RegulationDayRule()

    /// 責務: 曜日コードごとに、水曜・土曜・日曜の期待値の表(仕様書のコード表と管理役の判断から手で書いたもの)を作ります。
    private var expectations: [(code: String, wednesday: RegulationApplicability, saturday: RegulationApplicability, sunday: RegulationApplicability)] {
        [
            ("1", .doesNotApply, .applies, .applies),
            ("2", .unknown, .applies, .applies),
            ("3", .unknown, .unknown, .applies),
            ("4", .doesNotApply, .applies, .doesNotApply),
            ("5", .doesNotApply, .doesNotApply, .applies),
            ("6", .unknown, .unknown, .unknown),
            ("99", .unknown, .unknown, .unknown),
            ("7", .unknown, .unknown, .unknown),
            ("abc", .unknown, .unknown, .unknown),
        ]
    }

    /// 責務: 全コード × 水曜・土曜・日曜の判定が表どおりであることを確かめます。
    func testEveryCodeAgainstWeekdaySaturdayAndSunday() {
        for row in expectations {
            XCTAssertEqual(rule.evaluate(dayCode: row.code, on: RoadRegulationTokyoClock.wednesday()), row.wednesday, "コード \(row.code) 水曜")
            XCTAssertEqual(rule.evaluate(dayCode: row.code, on: RoadRegulationTokyoClock.saturday()), row.saturday, "コード \(row.code) 土曜")
            XCTAssertEqual(rule.evaluate(dayCode: row.code, on: RoadRegulationTokyoClock.sunday()), row.sunday, "コード \(row.code) 日曜")
        }
    }

    /// 責務: コードが無ければ曜日の制約なしとして、どの曜日でも適用になることを確かめます。
    func testNilCodeAppliesOnEveryDay() {
        XCTAssertEqual(rule.evaluate(dayCode: nil, on: RoadRegulationTokyoClock.wednesday()), .applies)
        XCTAssertEqual(rule.evaluate(dayCode: nil, on: RoadRegulationTokyoClock.saturday()), .applies)
        XCTAssertEqual(rule.evaluate(dayCode: nil, on: RoadRegulationTokyoClock.sunday()), .applies)
    }

    /// 責務: 日本時間の 00:00 と 23:59 で、同じ日(協定世界時では前日・翌日)として判定されることを確かめます。
    func testDayIsDecidedInTokyoAroundMidnight() {
        let saturdayEarly = RoadRegulationTokyoClock.saturday(0, 0)
        let saturdayLate = RoadRegulationTokyoClock.saturday(23, 59)
        XCTAssertEqual(rule.evaluate(dayCode: "4", on: saturdayEarly), .applies)
        XCTAssertEqual(rule.evaluate(dayCode: "4", on: saturdayLate), .applies)
        let sundayEarly = RoadRegulationTokyoClock.sunday(0, 30)
        XCTAssertEqual(rule.evaluate(dayCode: "5", on: sundayEarly), .applies)
        XCTAssertEqual(rule.evaluate(dayCode: "4", on: sundayEarly), .doesNotApply)
    }

    /// 責務: 端末のタイムゾーンを変えても結果が変わらないことを確かめます。
    func testResultIsIndependentOfDeviceTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let saturdayEarly = RoadRegulationTokyoClock.saturday(2, 0)
        for identifier in ["America/Los_Angeles", "UTC", "Pacific/Auckland"] {
            guard let zone = TimeZone(identifier: identifier) else {
                XCTFail("タイムゾーンを作れません: \(identifier)")
                continue
            }
            NSTimeZone.default = zone
            XCTAssertEqual(rule.evaluate(dayCode: "4", on: saturdayEarly), .applies, identifier)
            XCTAssertEqual(rule.evaluate(dayCode: "5", on: saturdayEarly), .doesNotApply, identifier)
        }
    }
}
