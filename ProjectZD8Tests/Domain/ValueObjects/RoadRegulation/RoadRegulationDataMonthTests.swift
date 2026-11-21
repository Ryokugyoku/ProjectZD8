import XCTest
@testable import ProjectZD8

/// `RoadRegulationDataMonth` の初期化の成功と失敗の境界、文字列の解釈、順序を検証します。
final class RoadRegulationDataMonthTests: XCTestCase {
    /// 責務: 年(2000〜2999)と月(1〜12)の境界が、ちょうどは成功・1外れると失敗になることを確かめます。
    func testYearAndMonthBoundaries() {
        XCTAssertNotNil(RoadRegulationDataMonth(year: 2000, month: 1))
        XCTAssertNotNil(RoadRegulationDataMonth(year: 2999, month: 12))
        XCTAssertNil(RoadRegulationDataMonth(year: 1999, month: 12))
        XCTAssertNil(RoadRegulationDataMonth(year: 3000, month: 1))
        XCTAssertNil(RoadRegulationDataMonth(year: 2026, month: 0))
        XCTAssertNil(RoadRegulationDataMonth(year: 2026, month: 13))
        XCTAssertNil(RoadRegulationDataMonth(year: 2026, month: -1))
    }

    /// 責務: 定数の範囲が仕様どおりであることを確かめます。
    func testValidRanges() {
        XCTAssertEqual(RoadRegulationDataMonth.validYears, 2000...2999)
        XCTAssertEqual(RoadRegulationDataMonth.validMonths, 1...12)
    }

    /// 責務: 6桁の ASCII 数字(yyyymm)が年と月に分けて読まれることを確かめます。
    func testYyyymmParsing() {
        let month = RoadRegulationDataMonth(yyyymm: "202611")
        XCTAssertEqual(month?.year, 2026)
        XCTAssertEqual(month?.month, 11)
        XCTAssertEqual(RoadRegulationDataMonth(yyyymm: "200001")?.month, 1)
        XCTAssertEqual(RoadRegulationDataMonth(yyyymm: "299912")?.year, 2999)
    }

    /// 責務: 桁数の違い・数字以外・範囲外の月や年の yyyymm が失敗することを確かめます。
    func testInvalidYyyymmFails() {
        for text in ["", "20261", "2026111", "2026-1", "20261x", " 202611", "202611 ", "202600", "202613", "199912", "300001", "２０２６１１"] {
            XCTAssertNil(RoadRegulationDataMonth(yyyymm: text), "「\(text)」")
        }
    }

    /// 責務: 年、同じ年なら月の順で比較され、等しいものは等しいことを確かめます。
    func testOrdering() throws {
        let nov2026 = try XCTUnwrap(RoadRegulationDataMonth(year: 2026, month: 11))
        let dec2026 = try XCTUnwrap(RoadRegulationDataMonth(year: 2026, month: 12))
        let jan2027 = try XCTUnwrap(RoadRegulationDataMonth(year: 2027, month: 1))
        XCTAssertLessThan(nov2026, dec2026)
        XCTAssertLessThan(dec2026, jan2027)
        XCTAssertGreaterThan(jan2027, nov2026)
        let sameMonth = try XCTUnwrap(RoadRegulationDataMonth(yyyymm: "202611"))
        XCTAssertFalse(nov2026 < sameMonth)
        XCTAssertFalse(sameMonth < nov2026)
        XCTAssertEqual(nov2026, RoadRegulationDataMonth(yyyymm: "202611"))
    }
}
