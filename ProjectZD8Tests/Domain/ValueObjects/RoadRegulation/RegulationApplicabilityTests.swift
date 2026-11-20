import XCTest
@testable import ProjectZD8

/// `RegulationApplicability` のクリーネの3値論理(and / or / not)を、真理値表の全組み合わせで検証します。
final class RegulationApplicabilityTests: XCTestCase {
    private typealias Value = RegulationApplicability
    private let applies = Value.applies
    private let doesNot = Value.doesNotApply
    private let unknown = Value.unknown

    /// 責務: and の9通りを、手で書いた真理値表と照らします(1つでも偽なら偽、全て真なら真、それ以外は不明)。
    func testAndTruthTable() {
        let table: [(Value, Value, Value)] = [
            (applies, applies, applies), (applies, doesNot, doesNot), (applies, unknown, unknown),
            (doesNot, applies, doesNot), (doesNot, doesNot, doesNot), (doesNot, unknown, doesNot),
            (unknown, applies, unknown), (unknown, doesNot, doesNot), (unknown, unknown, unknown),
        ]
        for (lhs, rhs, expected) in table {
            XCTAssertEqual(lhs.and(rhs), expected, "\(lhs) and \(rhs)")
        }
    }

    /// 責務: or の9通りを、手で書いた真理値表と照らします(1つでも真なら真、全て偽なら偽、それ以外は不明)。
    func testOrTruthTable() {
        let table: [(Value, Value, Value)] = [
            (applies, applies, applies), (applies, doesNot, applies), (applies, unknown, applies),
            (doesNot, applies, applies), (doesNot, doesNot, doesNot), (doesNot, unknown, unknown),
            (unknown, applies, applies), (unknown, doesNot, unknown), (unknown, unknown, unknown),
        ]
        for (lhs, rhs, expected) in table {
            XCTAssertEqual(lhs.or(rhs), expected, "\(lhs) or \(rhs)")
        }
    }

    /// 責務: not の3通りを確かめます(不明は不明のまま)。
    func testNegation() {
        XCTAssertEqual(applies.negated, doesNot)
        XCTAssertEqual(doesNot.negated, applies)
        XCTAssertEqual(unknown.negated, unknown)
    }

    /// 責務: 二重否定で元に戻ることと、ド・モルガンの法則が全組み合わせで成り立つことを確かめます。
    func testDoubleNegationAndDeMorgan() {
        let all: [Value] = [applies, doesNot, unknown]
        for lhs in all {
            XCTAssertEqual(lhs.negated.negated, lhs)
            for rhs in all {
                XCTAssertEqual(lhs.and(rhs).negated, lhs.negated.or(rhs.negated), "\(lhs), \(rhs)")
                XCTAssertEqual(lhs.and(rhs), rhs.and(lhs), "and の交換 \(lhs), \(rhs)")
                XCTAssertEqual(lhs.or(rhs), rhs.or(lhs), "or の交換 \(lhs), \(rhs)")
            }
        }
    }
}
