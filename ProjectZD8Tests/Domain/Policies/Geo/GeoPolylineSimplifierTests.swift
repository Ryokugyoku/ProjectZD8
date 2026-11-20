import XCTest
@testable import ProjectZD8

/// `GeoPolylineSimplifier` の間引きを、設計書 §2.2・§3.1・§9 T3-3 で検証します。
@MainActor
final class GeoPolylineSimplifierTests: XCTestCase {
    private let simplifier = GeoPolylineSimplifier()
    private let geo = GeoTestCoordinates()

    /// 責務: 東向きに 10 m おきの一直線の点を n 個作ります。
    private func straightLine(count: Int) -> [GeoCoordinate] {
        GeoPolylineFixtures.zigzag(count: count, step: 10, amplitude: 0)
    }

    /// 責務: 折れ線の合計の点数を返します。
    private func total(_ polylines: [[GeoCoordinate]]) -> Int {
        polylines.reduce(0) { $0 + $1.count }
    }

    /// 責務: 結果の各折れ線が、元の折れ線の端点を残し、2点以上であることを確かめます。
    private func assertKeepsEndpoints(_ result: [[GeoCoordinate]], of input: [[GeoCoordinate]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.count, input.count, file: file, line: line)
        for (output, source) in zip(result, input) {
            XCTAssertEqual(output.first, source.first, file: file, line: line)
            XCTAssertEqual(output.last, source.last, file: file, line: line)
            XCTAssertGreaterThanOrEqual(output.count, 2, file: file, line: line)
        }
    }

    // MARK: 上限以下・空・小さい入力

    /// 責務: 合計の点数が上限以下なら、一直線でも入力のまま返すことを確かめます。
    func testWithinBudgetReturnsInputUnchanged() {
        let line = straightLine(count: 10)
        XCTAssertEqual(simplifier.simplify([line], pointBudget: 10), [line])
        XCTAssertEqual(simplifier.simplify([line], pointBudget: 100), [line])
    }

    /// 責務: 上限を1点だけ超えると、間引きが働いて上限以下になることを確かめます。
    func testOneOverBudgetIsReduced() {
        let result = simplifier.simplify([straightLine(count: 10)], pointBudget: 9)
        XCTAssertLessThanOrEqual(total(result), 9)
    }

    /// 責務: 折れ線が1本も無い入力が空で返ることを確かめます。
    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(simplifier.simplify([], pointBudget: 10), [])
    }

    /// 責務: 1点の折れ線は、上限が小さくてもそのまま残ることを確かめます。
    func testSinglePointPolylineIsKept() {
        let single = geo.points([(x: 5, y: 5)])
        XCTAssertEqual(simplifier.simplify([single], pointBudget: 1), [single])
        XCTAssertEqual(simplifier.simplify([single, straightLine(count: 50)], pointBudget: 3)[0], single)
    }

    /// 責務: 2点の折れ線は、上限が小さくてもそのまま残ることを確かめます。
    func testTwoPointPolylineIsKept() {
        let pair = geo.points([(x: 0, y: 0), (x: 100, y: 50)])
        XCTAssertEqual(simplifier.simplify([pair], pointBudget: 2), [pair])
        XCTAssertEqual(simplifier.simplify([pair], pointBudget: 1), [pair])
    }

    // MARK: 形の保存

    /// 責務: 一直線の多数の点が、端点の2つだけになることを確かめます。
    func testStraightLineCollapsesToEndpoints() {
        let line = straightLine(count: 100)
        XCTAssertEqual(simplifier.simplify([line], pointBudget: 10), [[line[0], line[99]]])
    }

    /// 責務: 許容誤差 1 m 未満の細かい揺れ(0.3 m)の点が、端点だけに間引かれることを確かめます。
    func testSubMeterNoiseIsRemoved() {
        let line = GeoPolylineFixtures.zigzag(count: 200, step: 5, amplitude: 0.3)
        XCTAssertEqual(simplifier.simplify([line], pointBudget: 50), [[line[0], line[199]]])
    }

    /// 責務: L字の鋭い角が残り、直線部分の点だけが除かれる(3点になる)ことを確かめます。
    func testSharpCornerIsKept() {
        var line: [GeoCoordinate] = []
        for step in 0...10 { line.append(geo.point(x: Double(step) * 100, y: 0)) }
        for step in 1...10 { line.append(geo.point(x: 1_000, y: Double(step) * 100)) }
        let corner = geo.point(x: 1_000, y: 0)
        let result = simplifier.simplify([line], pointBudget: 10)
        XCTAssertEqual(result, [[line[0], corner, line[line.count - 1]]])
    }

    /// 責務: 揺れが 3 m の点を持つ線が、上限以下になり端点を残すことを確かめます。
    func testModerateZigzagIsReducedWithinBudget() {
        let line = GeoPolylineFixtures.zigzag(count: 200, step: 5, amplitude: 3)
        let result = simplifier.simplify([line], pointBudget: 50)
        XCTAssertLessThanOrEqual(total(result), 50)
        assertKeepsEndpoints(result, of: [line])
    }

    // MARK: 上限・端点・順序

    /// 責務: 円弧の線で上限をいくつか変えても、点数が上限以下で、端点と順序が保たれることを確かめます。
    func testArcRespectsEveryBudgetAndKeepsOrder() {
        let arc = GeoPolylineFixtures.arc(count: 1_000, radius: 500)
        for budget in [2, 5, 20, 100] {
            let result = simplifier.simplify([arc], pointBudget: budget)
            XCTAssertLessThanOrEqual(total(result), budget, "budget \(budget)")
            assertKeepsEndpoints(result, of: [arc])
            XCTAssertTrue(isSubsequence(result[0], of: arc), "budget \(budget)")
        }
    }

    /// 責務: 複数の折れ線の端点がそれぞれ残り、各折れ線が2点以上であることを確かめます。
    func testEveryPolylineKeepsItsEndpoints() {
        let lines: [[GeoCoordinate]] = (0..<5).map { offset in
            GeoPolylineFixtures.zigzag(count: 100, step: 10, amplitude: 0, baseY: Double(offset) * 1_000)
        }
        let result = simplifier.simplify(lines, pointBudget: 20)
        assertKeepsEndpoints(result, of: lines)
        XCTAssertLessThanOrEqual(total(result), 20)
    }

    /// 責務: 上限が「本数 × 2」未満の時は、各折れ線が端点だけになることを確かめます。
    func testBudgetBelowTwicePolylineCountLeavesEndpointsOnly() {
        let lines: [[GeoCoordinate]] = (0..<2).map { offset in
            GeoPolylineFixtures.zigzag(count: 100, step: 10, amplitude: 800, baseY: Double(offset) * 1_000)
        }
        let result = simplifier.simplify(lines, pointBudget: 3)
        XCTAssertEqual(result, lines.map { [$0[0], $0[99]] })
    }

    /// 責務: 上限が 1(1本の折れ線で2点未満)の時は、端点の2つだけになることを確かめます。
    func testBudgetOfOneKeepsEndpointsOnly() {
        let line = GeoPolylineFixtures.zigzag(count: 50, step: 10, amplitude: 900)
        XCTAssertEqual(simplifier.simplify([line], pointBudget: 1), [[line[0], line[49]]])
    }

    /// 責務: 256 m の許容誤差でも上限を超える(大きなジグザグ)時、等間隔に間引いて上限以下にすることを確かめます。
    func testFallsBackToEvenThinningBeyondMaximumTolerance() {
        let line = GeoPolylineFixtures.zigzag(count: 2_000, step: 10, amplitude: 1_000)
        let result = simplifier.simplify([line], pointBudget: 300)
        XCTAssertLessThanOrEqual(total(result), 300)
        XCTAssertGreaterThan(total(result), 100, "鋭く折れた点を一律に捨てず、等間隔に残します")
        assertKeepsEndpoints(result, of: [line])
        XCTAssertTrue(isSubsequence(result[0], of: line))
    }

    /// 責務: 多数の折れ線の各角が 256 m でも残る時、全体を上限以下にしつつ各端点を残すことを確かめます。
    func testManyPolylinesFallBackToEvenThinningKeepingEndpoints() {
        let lines = (0..<100).map { index in
            geo.points([(x: 0, y: Double(index) * 5_000), (x: 1_000, y: Double(index) * 5_000), (x: 1_000, y: Double(index) * 5_000 + 1_000)])
        }
        let result = simplifier.simplify(lines, pointBudget: 250)
        XCTAssertLessThanOrEqual(total(result), 250)
        assertKeepsEndpoints(result, of: lines)
    }

    // MARK: 補助

    /// 責務: 結果が元の点の列の部分列(順序を保った抜き出し)であるかを返します。
    private func isSubsequence(_ candidate: [GeoCoordinate], of source: [GeoCoordinate]) -> Bool {
        var cursor = source.startIndex
        for coordinate in candidate {
            guard let found = source[cursor...].firstIndex(of: coordinate) else { return false }
            cursor = source.index(after: found)
        }
        return true
    }
}
