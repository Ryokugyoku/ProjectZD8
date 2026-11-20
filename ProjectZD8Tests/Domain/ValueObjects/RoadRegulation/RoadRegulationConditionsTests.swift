import XCTest
@testable import ProjectZD8

/// `RoadRegulationConditions` の、対象・除外を5件へ揃える挙動と、符号化の往復を検証します。
final class RoadRegulationConditionsTests: XCTestCase {
    /// 責務: 時間の開始値で見分けられる条件の組を作ります。
    private func set(_ marker: String) -> RoadRegulationConditionSet {
        RoadRegulationConditionSet(timeStart: marker)
    }

    /// 責務: 件数の定数が5であることを確かめます。
    func testSetCountIsFive() {
        XCTAssertEqual(RoadRegulationConditions.setCount, 5)
    }

    /// 責務: 5件に満たない入力が、末尾を空の組で埋めて5件になることを確かめます。
    func testShortListsArePaddedWithEmptySets() {
        let conditions = RoadRegulationConditions(targets: [set("1"), set("2")], exclusions: [])
        XCTAssertEqual(conditions.targets.count, 5)
        XCTAssertEqual(conditions.exclusions.count, 5)
        XCTAssertEqual(conditions.targets.map(\.timeStart), ["1", "2", nil, nil, nil])
        XCTAssertTrue(conditions.exclusions.allSatisfy(\.isEmpty))
    }

    /// 責務: 5件ちょうどはそのまま、6件以上は先頭の5件に切られることを確かめます。
    func testExactAndOverlongListsAreFitted() {
        let five = (1...5).map { set("\($0)") }
        XCTAssertEqual(RoadRegulationConditions(targets: five, exclusions: five).targets, five)
        let seven = (1...7).map { set("\($0)") }
        let conditions = RoadRegulationConditions(targets: seven, exclusions: seven)
        XCTAssertEqual(conditions.targets.map(\.timeStart), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(conditions.exclusions.map(\.timeStart), ["1", "2", "3", "4", "5"])
    }

    /// 責務: すべて空の条件が無条件(isUnconditional)で、1件でも値があれば無条件でないことを確かめます。
    func testIsUnconditional() {
        XCTAssertTrue(RoadRegulationConditions.unconditional.isUnconditional)
        XCTAssertTrue(RoadRegulationConditions(targets: [.empty], exclusions: [.empty]).isUnconditional)
        XCTAssertFalse(RoadRegulationConditions(targets: [set("1")], exclusions: []).isUnconditional)
        XCTAssertFalse(RoadRegulationConditions(targets: [], exclusions: [set("1")]).isUnconditional)
    }

    /// 責務: 符号化して復号しても同じ値に戻ることを確かめます。
    func testCodableRoundTrip() throws {
        let original = RoadRegulationConditions(targets: [set("700")], exclusions: [RoadRegulationConditionSet(dayCode: "1")])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(RoadRegulationConditions.self, from: data), original)
    }

    /// 責務: 復号でも件数が5件へ揃えられる(短い配列を読んでも5件になる)ことを確かめます。
    func testDecodingFitsToFiveSets() throws {
        let short = RoadRegulationConditions(targets: [set("1")], exclusions: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(short))
        guard var object = json as? [String: Any] else { return XCTFail("JSON の形が想定と違います") }
        object["targets"] = Array((object["targets"] as? [Any] ?? []).prefix(1))
        object["exclusions"] = [Any]()
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RoadRegulationConditions.self, from: data)
        XCTAssertEqual(decoded.targets.count, 5)
        XCTAssertEqual(decoded.exclusions.count, 5)
        XCTAssertEqual(decoded.targets.first?.timeStart, "1")
    }
}
