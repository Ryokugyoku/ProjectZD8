import XCTest
@testable import ProjectZD8

/// `RoadRegulationConditionSet` の、前後の空白の除去と空項目の nil 化を検証します。
final class RoadRegulationConditionSetTests: XCTestCase {
    /// 責務: 既定の組が空であることを確かめます。
    func testDefaultIsEmpty() {
        XCTAssertTrue(RoadRegulationConditionSet().isEmpty)
        XCTAssertTrue(RoadRegulationConditionSet.empty.isEmpty)
    }

    /// 責務: 空文字・空白・改行だけの項目が nil になり、空の組として扱われることを確かめます。
    func testBlankFieldsBecomeNil() {
        let set = RoadRegulationConditionSet(periodStart: "", timeStart: "  ", dayCode: "\n\t", vehicleCodeA: " \n ")
        XCTAssertNil(set.periodStart)
        XCTAssertNil(set.timeStart)
        XCTAssertNil(set.dayCode)
        XCTAssertNil(set.vehicleCodeA)
        XCTAssertTrue(set.isEmpty)
    }

    /// 責務: 前後の空白と改行が除かれ、中の文字は保たれることを確かめます。
    func testSurroundingWhitespaceIsTrimmed() {
        let set = RoadRegulationConditionSet(timeStart: " 700\n", timeEnd: "\t900 ", vehicleCodeD: "10 00")
        XCTAssertEqual(set.timeStart, "700")
        XCTAssertEqual(set.timeEnd, "900")
        XCTAssertEqual(set.vehicleCodeD, "10 00")
        XCTAssertFalse(set.isEmpty)
    }

    /// 責務: 9項目のどれか1つだけに値があっても、空でないことを確かめます。
    func testAnySingleFieldMakesSetNonEmpty() {
        let sets = [
            RoadRegulationConditionSet(periodStart: "101"), RoadRegulationConditionSet(periodEnd: "101"),
            RoadRegulationConditionSet(timeStart: "0"), RoadRegulationConditionSet(timeEnd: "0"),
            RoadRegulationConditionSet(dayCode: "1"), RoadRegulationConditionSet(vehicleCodeA: "1"),
            RoadRegulationConditionSet(vehicleCodeB: "1"), RoadRegulationConditionSet(vehicleCodeC: "1"),
            RoadRegulationConditionSet(vehicleCodeD: "1"),
        ]
        XCTAssertEqual(sets.count, 9)
        XCTAssertTrue(sets.allSatisfy { !$0.isEmpty })
    }
}
