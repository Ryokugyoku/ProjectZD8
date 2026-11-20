import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICRegulationRowParser` の §3.1 の規則1〜5(項目数・種別・廃止・ユニークキー・形状コード)を、上から順の優先も含めて検証します。
@MainActor
final class JARTICRegulationRowParserTests: XCTestCase {
    private typealias Builder = TestJARTICRegulationRowBuilder
    private typealias Expect = TestJARTICRegulationRecordExpectation

    // MARK: 規則1 項目数

    /// 項目数が見出しより少ない行は `fieldCountMismatch` で破棄します。
    func testFewerFieldsThanHeaderIsRejected() throws {
        Expect.assertRejected(try Builder.parse(fieldCountOffset: -1), .fieldCountMismatch)
    }

    /// 項目数が見出しより多い行も `fieldCountMismatch` です。
    func testMoreFieldsThanHeaderIsRejected() throws {
        Expect.assertRejected(try Builder.parse(fieldCountOffset: 1), .fieldCountMismatch)
    }

    /// 項目数の違反は、種別の判定より先です(対象外の種別でも破棄になる)。
    func testFieldCountMismatchTakesPriorityOverOutOfScopeKind() throws {
        Expect.assertRejected(try Builder.parse(kind: 999, fieldCountOffset: 1), .fieldCountMismatch)
    }

    /// 項目数が一致する行は採用されます。
    func testMatchingFieldCountIsAccepted() throws {
        let draft = try Expect.draft(try Builder.parse())
        XCTAssertEqual(draft.uniqueKey, "KEY0001")
    }

    // MARK: 規則2 種別

    /// 共通規制種別コードが整数でない(空・文字・小数)と `missingRequiredField` です。
    func testNonIntegerKindIsRejected() throws {
        for value in ["", "abc", "11.5"] {
            let record = try Builder.parse([JARTICColumnName.kindCode: value])
            Expect.assertRejected(record, .missingRequiredField)
        }
    }

    /// 対象の6種(112・113・114・63・11・61)は、それぞれ対応する種別で採用されます。
    func testEachInScopeKindIsAcceptedWithMatchingKind() throws {
        let expected: [Int: RoadRegulationKind] = [
            112: .speedLimitSection, 113: .speedLimitVariableSection, 114: .speedLimitZone,
            63: .stop, 11: .oneWay, 61: .slowDown,
        ]
        for (code, kind) in expected {
            let draft = try Expect.draft(try Builder.parse(kind: code))
            XCTAssertEqual(draft.kind, kind, "コード \(code)")
        }
    }

    /// 対象外の種別は、`skipped(.outOfScopeKind)` です(破棄ではない)。
    func testOutOfScopeKindIsSkipped() throws {
        for code in [0, 1, 12, 62, 64, 111, 115, 999] {
            Expect.assertSkipped(try Builder.parse(kind: code), .outOfScopeKind)
        }
    }

    // MARK: 規則3 廃止

    /// 意思決定廃止日が空でなければ `skipped(.abolished)` です。
    func testAbolishedDateIsSkipped() throws {
        Expect.assertSkipped(try Builder.parse([JARTICColumnName.abolishedOn: "20260101"]), .abolished)
    }

    /// データ更新区分コードが 3 でも `skipped(.abolished)` です。
    func testUpdateKindThreeIsSkipped() throws {
        Expect.assertSkipped(try Builder.parse([JARTICColumnName.updateKind: "3"]), .abolished)
    }

    /// 更新区分が 3 以外(1・2・4・5・空)で廃止日が空なら採用されます。
    func testOtherUpdateKindsAreAccepted() throws {
        for value in ["1", "2", "4", "5", ""] {
            let record = try Builder.parse([JARTICColumnName.updateKind: value])
            XCTAssertNotNil(try? Expect.draft(record), "更新区分 \(value)")
        }
    }

    /// 対象外の種別の判定は、廃止の判定より先です。
    func testOutOfScopeKindTakesPriorityOverAbolished() throws {
        let record = try Builder.parse([JARTICColumnName.abolishedOn: "20260101"], kind: 999)
        Expect.assertSkipped(record, .outOfScopeKind)
    }

    /// 廃止の判定は、ユニークキーの検査より先です(キーが空でも読み飛ばし)。
    func testAbolishedTakesPriorityOverMissingUniqueKey() throws {
        let record = try Builder.parse([JARTICColumnName.abolishedOn: "20260101", JARTICColumnName.uniqueKey: ""])
        Expect.assertSkipped(record, .abolished)
    }

    // MARK: 規則4 ユニークキー

    /// ユニークキーが空(空白だけを含む)なら `missingRequiredField` です。
    func testMissingUniqueKeyIsRejected() throws {
        for value in ["", "   "] {
            Expect.assertRejected(try Builder.parse([JARTICColumnName.uniqueKey: value]), .missingRequiredField)
        }
    }

    /// ユニークキーの検査は、形状コードの検査より先です。
    func testMissingUniqueKeyTakesPriorityOverShapeMismatch() throws {
        let record = try Builder.parse([JARTICColumnName.uniqueKey: "", JARTICColumnName.shapeCode: "3"])
        Expect.assertRejected(record, .missingRequiredField)
    }

    /// ユニークキーは前後の空白を除いて下書きに入ります。
    func testUniqueKeyIsStoredTrimmed() throws {
        let draft = try Expect.draft(try Builder.parse([JARTICColumnName.uniqueKey: " AB12cd "]))
        XCTAssertEqual(draft.uniqueKey, "AB12cd")
    }

    // MARK: 規則5 形状コード

    /// 種別ごとに期待する形状(点=1・線=2・面=3)以外の値は `shapeMismatch` です。
    func testShapeCodeDifferentFromExpectedIsRejected() throws {
        let expectedShape: [Int: Int] = [112: 2, 113: 2, 114: 3, 63: 1, 11: 2, 61: 2]
        for (kind, shape) in expectedShape {
            for wrong in (1...3).filter({ $0 != shape }) + [9] {
                let record = try Builder.parse([JARTICColumnName.shapeCode: String(wrong)], kind: kind)
                Expect.assertRejected(record, .shapeMismatch)
            }
        }
    }

    /// 形状コードの検査は、座標の検査より先です。
    func testShapeMismatchTakesPriorityOverInvalidCoordinates() throws {
        let record = try Builder.parse([JARTICColumnName.shapeCode: "3", JARTICColumnName.coordinates: "abc def"])
        Expect.assertRejected(record, .shapeMismatch)
    }
}
