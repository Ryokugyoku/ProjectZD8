import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICConditionSetParser` が、対象1〜5と除外1〜5の9項目ずつを、解釈せずそのまま正しい位置の組へ入れることを検証します。
@MainActor
final class JARTICConditionSetParserTests: XCTestCase {
    private let parser = JARTICConditionSetParser()

    private func conditions(_ overrides: [String: String]) throws -> RoadRegulationConditions {
        let header = try TestJARTICRegulationRowBuilder.header()
        let row = try TestJARTICRegulationRowBuilder.row(overrides)
        return parser.conditions(from: row, header: header)
    }

    /// 組の9項目それぞれに別の値を入れた列の上書きを作ります。
    private func overrides(set: Int, target: Bool, values: [JARTICConditionField: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (field, value) in values {
            let name = target ? JARTICColumnName.target(set, field) : JARTICColumnName.exclusion(set, field)
            result[name] = value
        }
        return result
    }

    private let targetValues: [JARTICConditionField: String] = [
        .periodStart: "0401", .periodEnd: "0930", .timeStart: "700", .timeEnd: "1900", .day: "4",
        .vehicleA: "1", .vehicleB: "10", .vehicleC: "100", .vehicleD: "1000",
    ]
    private let targetSet = RoadRegulationConditionSet(
        periodStart: "0401", periodEnd: "0930", timeStart: "700", timeEnd: "1900", dayCode: "4",
        vehicleCodeA: "1", vehicleCodeB: "10", vehicleCodeC: "100", vehicleCodeD: "1000"
    )
    private let exclusionValues: [JARTICConditionField: String] = [
        .periodStart: "1101", .periodEnd: "1231", .timeStart: "2200", .timeEnd: "400", .day: "5",
        .vehicleA: "10000", .vehicleB: "1", .vehicleC: "11", .vehicleD: "111",
    ]
    private let exclusionSet = RoadRegulationConditionSet(
        periodStart: "1101", periodEnd: "1231", timeStart: "2200", timeEnd: "400", dayCode: "5",
        vehicleCodeA: "10000", vehicleCodeB: "1", vehicleCodeC: "11", vehicleCodeD: "111"
    )

    /// 条件の列がすべて空なら、条件なしです。
    func testAllEmptyIsUnconditional() throws {
        let result = try conditions([:])
        XCTAssertEqual(result, .unconditional)
        XCTAssertTrue(result.isUnconditional)
    }

    /// 常に対象・除外とも5組ずつ返ります。
    func testAlwaysFiveSetsEach() throws {
        let result = try conditions([:])
        XCTAssertEqual(result.targets.count, 5)
        XCTAssertEqual(result.exclusions.count, 5)
    }

    /// 対象1の9項目が、それぞれ対応する項目に入ります(取り違えない)。
    func testTargetSetFieldsAreMappedToMatchingProperties() throws {
        let result = try conditions(overrides(set: 1, target: true, values: targetValues))
        XCTAssertEqual(result.targets[0], targetSet)
        XCTAssertTrue(result.targets.dropFirst().allSatisfy(\.isEmpty))
        XCTAssertTrue(result.exclusions.allSatisfy(\.isEmpty))
    }

    /// 除外1の9項目が、それぞれ対応する項目に入ります。
    func testExclusionSetFieldsAreMappedToMatchingProperties() throws {
        let result = try conditions(overrides(set: 1, target: false, values: exclusionValues))
        XCTAssertEqual(result.exclusions[0], exclusionSet)
        XCTAssertTrue(result.exclusions.dropFirst().allSatisfy(\.isEmpty))
        XCTAssertTrue(result.targets.allSatisfy(\.isEmpty))
    }

    /// 対象2の値は targets[1] に、除外3の値は exclusions[2] に入ります。
    func testTargetTwoAndExclusionThreeLandInCorrectPositions() throws {
        let values = overrides(set: 2, target: true, values: targetValues)
            .merging(overrides(set: 3, target: false, values: exclusionValues)) { first, _ in first }
        let result = try conditions(values)

        XCTAssertEqual(result.targets[1], targetSet)
        XCTAssertEqual(result.exclusions[2], exclusionSet)
        XCTAssertEqual(result.targets.enumerated().filter { $0.offset != 1 }.map(\.element), Array(repeating: .empty, count: 4))
        XCTAssertEqual(result.exclusions.enumerated().filter { $0.offset != 2 }.map(\.element), Array(repeating: .empty, count: 4))
    }

    /// 5組すべて(対象・除外とも)に、組ごとに別の値を入れても、順序どおりに保存されます。
    func testAllFiveSetsKeepTheirOwnValues() throws {
        var values: [String: String] = [:]
        for set in 1...5 {
            values[JARTICColumnName.target(set, .timeStart)] = "\(set)00"
            values[JARTICColumnName.exclusion(set, .day)] = "9\(set)"
        }
        let result = try conditions(values)

        XCTAssertEqual(result.targets.map(\.timeStart), ["100", "200", "300", "400", "500"])
        XCTAssertEqual(result.targets.compactMap(\.dayCode), [])
        XCTAssertEqual(result.exclusions.map(\.dayCode), ["91", "92", "93", "94", "95"])
    }

    /// 値は解釈せず、そのまま保存します(先頭の0なし・日付をまたぐ時間・2400・99・意味のない文字列)。
    func testValuesAreStoredVerbatimWithoutInterpretation() throws {
        let result = try conditions([
            JARTICColumnName.target(1, .timeStart): "0",
            JARTICColumnName.target(1, .timeEnd): "2400",
            JARTICColumnName.target(2, .timeStart): "2200",
            JARTICColumnName.target(2, .timeEnd): "400",
            JARTICColumnName.target(1, .day): "99",
            JARTICColumnName.target(1, .periodStart): "1231",
            JARTICColumnName.target(1, .periodEnd): "0101",
            JARTICColumnName.target(1, .vehicleA): "abc",
        ])

        XCTAssertEqual(result.targets[0].timeStart, "0")
        XCTAssertEqual(result.targets[0].timeEnd, "2400")
        XCTAssertEqual(result.targets[1].timeStart, "2200")
        XCTAssertEqual(result.targets[1].timeEnd, "400")
        XCTAssertEqual(result.targets[0].dayCode, "99")
        XCTAssertEqual(result.targets[0].periodStart, "1231")
        XCTAssertEqual(result.targets[0].periodEnd, "0101")
        XCTAssertEqual(result.targets[0].vehicleCodeA, "abc")
    }

    /// 前後の空白は取り除いて保存し、空白だけの項目は空(nil)になります。
    func testSurroundingWhitespaceIsTrimmedAndBlankBecomesNil() throws {
        let result = try conditions([
            JARTICColumnName.target(1, .day): " 4 ",
            JARTICColumnName.target(1, .vehicleA): "   ",
        ])

        XCTAssertEqual(result.targets[0].dayCode, "4")
        XCTAssertNil(result.targets[0].vehicleCodeA)
    }

    /// 対象と除外は別の列から読み、混ざりません(同じ組番号・同じ項目でも)。
    func testTargetAndExclusionOfSameIndexAreIndependent() throws {
        let result = try conditions([
            JARTICColumnName.target(4, .day): "1",
            JARTICColumnName.exclusion(4, .day): "5",
        ])

        XCTAssertEqual(result.targets[3].dayCode, "1")
        XCTAssertEqual(result.exclusions[3].dayCode, "5")
    }
}
