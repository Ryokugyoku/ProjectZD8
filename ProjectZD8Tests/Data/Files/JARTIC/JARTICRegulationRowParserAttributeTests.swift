import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRegulationRowParser` の §3.1 の規則10〜13(速度・一方通行の別・片側両側・外周道路・条件)を検証します。
@MainActor
final class JARTICRegulationRowParserAttributeTests: XCTestCase {
    private typealias Builder = TestJARTICRegulationRowBuilder
    private typealias Expect = TestJARTICRegulationRecordExpectation

    // MARK: 規則10 速度

    /// 最高速度(区間 112・区域 114)は、1〜120 の整数なら採用します(端を含む)。
    func testSpeedWithinRangeIsAccepted() throws {
        for kind in [112, 114] {
            for value in [1, 30, 120] {
                let draft = try Expect.draft(try Builder.parse([JARTICColumnName.speed: String(value)], kind: kind))
                XCTAssertEqual(draft.speedLimitKph, value, "種別 \(kind) 速度 \(value)")
            }
        }
    }

    /// 速度の前後の空白は無視します。
    func testSpeedWithSurroundingWhitespaceIsAccepted() throws {
        let draft = try Expect.draft(try Builder.parse([JARTICColumnName.speed: " 30 "]))
        XCTAssertEqual(draft.speedLimitKph, 30)
    }

    /// 速度が 0・121・負・空・小数・文字なら `invalidSpeed` です(112 と 114)。
    func testSpeedOutOfRangeOrMalformedIsRejected() throws {
        for kind in [112, 114] {
            for value in ["0", "121", "-1", "", "40.5", "abc"] {
                let record = try Builder.parse([JARTICColumnName.speed: value], kind: kind)
                Expect.assertRejected(record, .invalidSpeed)
            }
        }
    }

    /// 可変(113)は、速度の欄が何であっても `nil` にして採用します。
    func testVariableSpeedIgnoresSpeedColumn() throws {
        for value in ["40", "", "abc", "0"] {
            let draft = try Expect.draft(try Builder.parse([JARTICColumnName.speed: value], kind: 113))
            XCTAssertNil(draft.speedLimitKph, "速度の欄 \(value)")
        }
    }

    /// 最高速度以外の種別(63・11・61)は速度を読みません(欄が不正でも採用で `nil`)。
    func testOtherKindsDoNotReadSpeed() throws {
        for kind in [63, 11, 61] {
            let draft = try Expect.draft(try Builder.parse([JARTICColumnName.speed: "abc"], kind: kind))
            XCTAssertNil(draft.speedLimitKph, "種別 \(kind)")
        }
    }

    // MARK: 規則11 一方通行

    /// 指定・禁止方向の別コードが 1 は禁止する向き、2 は指定する向きです。
    func testOneWayOrderOneAndTwo() throws {
        let prohibited = try Expect.draft(try Builder.parse([JARTICColumnName.oneWayOrder: "1"], kind: 11))
        let permitted = try Expect.draft(try Builder.parse([JARTICColumnName.oneWayOrder: "2"], kind: 11))
        XCTAssertEqual(prohibited.oneWayOrder, .prohibitedDirection)
        XCTAssertEqual(permitted.oneWayOrder, .permittedDirection)
    }

    /// 別コードが空・0・3・文字なら `invalidOneWayOrder` です。
    func testOneWayOrderOtherValuesAreRejected() throws {
        for value in ["", "0", "3", "x"] {
            let record = try Builder.parse([JARTICColumnName.oneWayOrder: value], kind: 11)
            Expect.assertRejected(record, .invalidOneWayOrder)
        }
    }

    /// 一方通行以外の種別では別コードを読みません(`nil`)。
    func testOneWayOrderIsNilForOtherKinds() throws {
        let draft = try Expect.draft(try Builder.parse([JARTICColumnName.oneWayOrder: "2"], kind: 112))
        XCTAssertNil(draft.oneWayOrder)
    }

    // MARK: 規則12 片側・両側と外周道路

    /// 片側・両側コードの 1 / 2 / 3 は、その値になります。
    func testSideCodeKnownValues() throws {
        let expected: [String: RoadRegulationSideCode] = ["1": .none, "2": .oneSide, "3": .bothSides]
        for (value, side) in expected {
            let draft = try Expect.draft(try Builder.parse([JARTICColumnName.side: value]))
            XCTAssertEqual(draft.side, side, "コード \(value)")
        }
    }

    /// 片側・両側コードが空・0・4・文字なら `nil` です(破棄しない)。
    func testSideCodeOtherValuesAreNil() throws {
        for value in ["", "0", "4", "x"] {
            let draft = try Expect.draft(try Builder.parse([JARTICColumnName.side: value]))
            XCTAssertNil(draft.side, "コード \(value)")
        }
    }

    /// 外周道路有無コードは 1 → true、2 → false、それ以外は `nil` です。
    func testPerimeterRoadCode() throws {
        let expected: [String: Bool?] = ["1": true, "2": false, "": nil, "0": nil, "3": nil, "x": nil]
        for (value, flag) in expected {
            let draft = try Expect.draft(try Builder.parse([JARTICColumnName.perimeterRoad: value], kind: 114))
            XCTAssertEqual(draft.perimeterRoadIncluded, flag, "コード \(value)")
        }
    }

    // MARK: 規則13 条件

    /// 条件の列がすべて空なら、条件なしで採用されます。
    func testUnconditionalRow() throws {
        let draft = try Expect.draft(try Builder.parse())
        XCTAssertEqual(draft.conditions, .unconditional)
    }

    /// 対象2と除外3の値は、正しい位置の組に、解釈されずに入ります。
    func testConditionsAreStoredInMatchingSets() throws {
        let draft = try Expect.draft(try Builder.parse([
            JARTICColumnName.target(2, .timeStart): "700",
            JARTICColumnName.target(2, .timeEnd): "1900",
            JARTICColumnName.target(2, .vehicleA): "1",
            JARTICColumnName.exclusion(3, .day): "5",
            JARTICColumnName.exclusion(3, .vehicleD): "100",
        ]))

        XCTAssertEqual(draft.conditions.targets[1], RoadRegulationConditionSet(timeStart: "700", timeEnd: "1900", vehicleCodeA: "1"))
        XCTAssertEqual(draft.conditions.exclusions[2], RoadRegulationConditionSet(dayCode: "5", vehicleCodeD: "100"))
        XCTAssertTrue(draft.conditions.targets.enumerated().allSatisfy { $0.offset == 1 || $0.element.isEmpty })
        XCTAssertTrue(draft.conditions.exclusions.enumerated().allSatisfy { $0.offset == 2 || $0.element.isEmpty })
    }
}
