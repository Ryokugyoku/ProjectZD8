import XCTest
@testable import ProjectZD8

/// `RouteAnalysisColorBands` の境界の検査と、値から区分への対応を検証します。
@MainActor
final class RouteAnalysisColorBandsTests: XCTestCase {
    private func bands(_ boundaries: [Double] = [20, 40, 60, 80]) throws -> RouteAnalysisColorBands {
        try XCTUnwrap(RouteAnalysisColorBands(boundaries: boundaries))
    }

    // MARK: init?

    /// 責務: 空の境界が nil になることを確かめます。
    func testEmptyBoundariesAreRejected() {
        XCTAssertNil(RouteAnalysisColorBands(boundaries: []))
    }

    /// 責務: NaN や無限大を含む境界が nil になることを確かめます。
    func testNonFiniteBoundariesAreRejected() {
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [10, .nan]))
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [.infinity]))
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [-.infinity, 10]))
    }

    /// 責務: 昇順でない境界(降順・同値の重複)が nil になることを確かめます。
    func testNonStrictlyAscendingBoundariesAreRejected() {
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [20, 10]))
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [10, 10]))
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [10, 20, 20, 30]))
        XCTAssertNil(RouteAnalysisColorBands(boundaries: [10, 30, 20]))
    }

    /// 責務: 1つだけの境界や負の境界を含む狭義の昇順が受け入れられ、境界がそのまま保たれることを確かめます。
    func testValidBoundariesAreAccepted() throws {
        XCTAssertEqual(try bands([5]).boundaries, [5])
        XCTAssertEqual(try bands([-10, 0, 10]).boundaries, [-10, 0, 10])
    }

    /// 責務: 区分の数が境界の数 + 1 であることを確かめます。
    func testStepCount() throws {
        XCTAssertEqual(try bands([5]).stepCount, 2)
        XCTAssertEqual(try bands().stepCount, 5)
    }

    // MARK: step(for:)

    /// 責務: 各区分の内側の値が、その区分の番号になることを確かめます。
    func testValuesInsideEachStep() throws {
        let value = try bands()
        let cases: [(Double, Int)] = [(10, 0), (30, 1), (50, 2), (70, 3), (90, 4)]
        for (input, expected) in cases {
            XCTAssertEqual(value.step(for: input), expected, "\(input)")
        }
    }

    /// 責務: 境界ちょうどの値が上の区分になることを確かめます。
    func testBoundaryValueBelongsToUpperStep() throws {
        let value = try bands()
        let cases: [(Double, Int)] = [(20, 1), (40, 2), (60, 3), (80, 4)]
        for (input, expected) in cases {
            XCTAssertEqual(value.step(for: input), expected, "\(input)")
        }
    }

    /// 責務: 境界のすぐ下とすぐ上の値が、それぞれ下・上の区分になることを確かめます。
    func testJustBelowAndAboveBoundary() throws {
        let value = try bands()
        XCTAssertEqual(value.step(for: 19.999), 0)
        XCTAssertEqual(value.step(for: 20.001), 1)
        XCTAssertEqual(value.step(for: 79.999), 3)
        XCTAssertEqual(value.step(for: 80.001), 4)
    }

    /// 責務: すべての境界以上の値が最後の区分(count)になることを確かめます。
    func testValuesAtOrAboveLastBoundaryAreLastStep() throws {
        let value = try bands()
        XCTAssertEqual(value.step(for: 80), 4)
        XCTAssertEqual(value.step(for: 10_000), 4)
    }

    /// 責務: 負の値と 0 が最初の区分(0)になることを確かめます。
    func testNegativeAndZeroAreFirstStep() throws {
        let value = try bands()
        XCTAssertEqual(value.step(for: -5), 0)
        XCTAssertEqual(value.step(for: -1_000_000), 0)
        XCTAssertEqual(value.step(for: 0), 0)
    }

    /// 責務: NaN と無限大が nil になることを確かめます。
    func testNonFiniteValuesHaveNoStep() throws {
        let value = try bands()
        XCTAssertNil(value.step(for: .nan))
        XCTAssertNil(value.step(for: .infinity))
        XCTAssertNil(value.step(for: -.infinity))
    }

    /// 責務: 境界が1つの区分で、境界ちょうどが上(1)になることを確かめます。
    func testSingleBoundary() throws {
        let value = try bands([5])
        XCTAssertEqual(value.step(for: 4.999), 0)
        XCTAssertEqual(value.step(for: 5), 1)
    }
}
