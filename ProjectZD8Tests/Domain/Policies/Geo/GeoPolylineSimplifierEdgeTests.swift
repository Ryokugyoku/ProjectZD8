import Foundation
import XCTest
@testable import ProjectZD8

/// `GeoPolylineSimplifier` の境界(点数の上限が極端な時、許容誤差の選び方、許容誤差の指定が不正な時)を検証します。
@MainActor
final class GeoPolylineSimplifierEdgeTests: XCTestCase {
    /// メートル単位の形状を座標へ直す補助です。
    private let geo = GeoTestCoordinates()
    /// 既定の許容誤差(1 m から 256 m)の間引きです。
    private let simplifier = GeoPolylineSimplifier()

    /// 責務: 折れ線の合計の点数を返します。
    private func total(_ polylines: [[GeoCoordinate]]) -> Int {
        polylines.reduce(0) { $0 + $1.count }
    }

    /// 責務: 東向きに 100 m 間隔の3点で、真ん中の点だけが北向きに offset ずれた折れ線を作ります(y の基準は baseY)。
    private func bump(offset: Double, baseY: Double) -> [GeoCoordinate] {
        geo.points([(x: 0, y: baseY), (x: 100, y: baseY + offset), (x: 200, y: baseY)])
    }

    /// 責務: 東向きに step 間隔で count 個並ぶ一直線の折れ線を作ります(y の基準は baseY)。
    private func straight(count: Int, step: Double, baseY: Double) -> [GeoCoordinate] {
        var meters: [(x: Double, y: Double)] = []
        for index in 0..<count {
            meters.append((x: Double(index) * step, y: baseY))
        }
        return geo.points(meters)
    }

    /// 責務: 折れ線の列の各折れ線が、入力の始点と終点だけであることを確かめます。
    private func assertEndpointsOnly(_ result: [[GeoCoordinate]], of input: [[GeoCoordinate]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.count, input.count, file: file, line: line)
        for (output, source) in zip(result, input) {
            let expected: [GeoCoordinate] = source.count >= 2 ? [source[0], source[source.count - 1]] : source
            XCTAssertEqual(output, expected, file: file, line: line)
        }
    }

    /// 責務: 結果の点が元の点の部分列で、内側の点が等間隔(間隔の差が1以下)に選ばれ、端点を残すことを確かめます。
    private func assertEvenlyThinned(_ output: [GeoCoordinate], from source: [GeoCoordinate], file: StaticString = #filePath, line: UInt = #line) {
        var indexOf: [GeoCoordinate: Int] = [:]
        for (position, point) in source.enumerated() { indexOf[point] = position }
        let indices: [Int] = output.compactMap { indexOf[$0] }
        XCTAssertEqual(indices.count, output.count, "元に無い点がある", file: file, line: line)
        XCTAssertEqual(indices.first, 0, file: file, line: line)
        XCTAssertEqual(indices.last, source.count - 1, file: file, line: line)
        let gaps: [Int] = zip(indices.dropFirst(), indices).map { $0 - $1 }
        XCTAssertTrue(gaps.allSatisfy { $0 > 0 }, "順序が保たれていない", file: file, line: line)
        XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), 1, "等間隔でない: \(gaps)", file: file, line: line)
    }

    /// 点数の上限が 0 や負でも落ちず、各折れ線の端点だけを返します。
    ///
    /// 責務: 上限 0・-1・Int.min で、2点以上の折れ線は端点2つ、1点の折れ線は1点になることを確認します。
    func testZeroOrNegativeBudgetReturnsEndpointsOnly() {
        let input = [GeoPolylineFixtures.zigzag(count: 10, step: 100, amplitude: 1_000), straight(count: 5, step: 10, baseY: 5_000), geo.points([(x: 1, y: 2)])]
        for budget in [0, -1, Int.min] {
            assertEndpointsOnly(simplifier.simplify(input, pointBudget: budget), of: input)
        }
    }

    /// 0点の折れ線は空のまま残り、本数と順序が入力と同じです。
    ///
    /// 責務: 空・1点・複数点の折れ線が混ざった入力で、並びが保たれることを確認します。
    func testEmptyPolylineStaysAndOrderIsPreserved() {
        let first = GeoPolylineFixtures.zigzag(count: 8, step: 100, amplitude: 1_000)
        let single = geo.points([(x: 7, y: 7)])
        let last = GeoPolylineFixtures.zigzag(count: 8, step: 100, amplitude: 1_000, baseY: 9_000)
        let input: [[GeoCoordinate]] = [[], first, [], single, last, []]
        let result = simplifier.simplify(input, pointBudget: 6)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result[0], [])
        XCTAssertEqual(result[2], [])
        XCTAssertEqual(result[5], [])
        XCTAssertEqual(result[3], single)
        XCTAssertEqual(result[1].first, first.first)
        XCTAssertEqual(result[1].last, first.last)
        XCTAssertEqual(result[4].first, last.first)
        XCTAssertEqual(result[4].last, last.last)
    }

    /// 上限が端点の数に届かない時は端点だけを返し、合計が上限を超えます。
    ///
    /// 責務: 2点以上の折れ線3本(端点6)に上限 5 と 6、1点の折れ線を含む入力に上限 4 を与えて確認します。
    func testBudgetBelowEndpointTotalKeepsEndpointsAndMayExceedBudget() {
        let lines = (0..<3).map { GeoPolylineFixtures.zigzag(count: 6, step: 100, amplitude: 1_000, baseY: Double($0) * 10_000) }
        for budget in [5, 6] {
            let result = simplifier.simplify(lines, pointBudget: budget)
            assertEndpointsOnly(result, of: lines)
            XCTAssertEqual(total(result), 6)
        }
        let mixed = [lines[0], geo.points([(x: 3, y: 3)]), lines[1]]
        let mixedResult = simplifier.simplify(mixed, pointBudget: 4)
        assertEndpointsOnly(mixedResult, of: mixed)
        XCTAssertEqual(total(mixedResult), 5)
    }

    /// 合計が上限以下の入力は、同じ点・同じ順でそのまま返します。
    ///
    /// 責務: 合計が上限より小さい場合とちょうど等しい場合で、入力と一致することを確認します。
    func testInputWithinBudgetIsReturnedAsIs() {
        let input = [GeoPolylineFixtures.zigzag(count: 20, step: 1, amplitude: 0.5), [], straight(count: 10, step: 3, baseY: 100)]
        XCTAssertEqual(total(input), 30)
        XCTAssertEqual(simplifier.simplify(input, pointBudget: 30), input)
        XCTAssertEqual(simplifier.simplify(input, pointBudget: 31), input)
        XCTAssertEqual(simplifier.simplify(input, pointBudget: 1_000), input)
    }

    /// 合計が上限以下になった最初の許容誤差の結果を返し、それ以上は進みません。
    ///
    /// 責務: 内側の点のずれが 1.5 m・3 m の2本と一直線の1本(合計9点)で、上限 8・7・6 の結果を確認します。
    func testFirstSufficientToleranceIsUsed() {
        let lines = [bump(offset: 1.5, baseY: 0), bump(offset: 3, baseY: 10_000), straight(count: 3, step: 100, baseY: 20_000)]
        let cases: [(budget: Int, counts: [Int])] = [(8, [3, 3, 2]), (7, [2, 3, 2]), (6, [2, 2, 2])]
        for testCase in cases {
            let result = simplifier.simplify(lines, pointBudget: testCase.budget)
            XCTAssertEqual(result.map(\.count), testCase.counts, "上限 \(testCase.budget)")
        }
        let kept = simplifier.simplify(lines, pointBudget: 8)
        XCTAssertEqual(kept[0], lines[0], "1 m で足りるので 1.5 m の点が残る")
        XCTAssertEqual(kept[1], lines[1])
    }

    /// ずれが許容誤差の少し内側の点は除かれ、少し外側の点は残ります。
    ///
    /// 責務: 許容誤差 4 m に対し 3.99 m と 4.01 m のずれの点を、上限 7 で確認します。
    func testPointJustInsideAndOutsideToleranceBoundary() {
        let inside = bump(offset: 3.99, baseY: 0)
        let outside = bump(offset: 4.01, baseY: 10_000)
        let lines = [inside, outside, straight(count: 3, step: 100, baseY: 20_000)]
        let result = simplifier.simplify(lines, pointBudget: 7)
        XCTAssertEqual(result[0], [inside[0], inside[2]])
        XCTAssertEqual(result[1], outside)
        XCTAssertEqual(result[2].count, 2)
    }

    /// 256 m の許容誤差まで試し、それ以上には進みません。
    ///
    /// 責務: ずれ 255 m の点は 256 m で除かれ、257 m の点は 256 m でも残る(512 m へ進まない)ことを確認します。
    func testMaximumToleranceOf256IsTriedButNotExceeded() {
        let dropped = geo.points([(x: 0, y: 0), (x: 1_000, y: 255), (x: 2_000, y: 0)])
        let kept = geo.points([(x: 0, y: 50_000), (x: 1_000, y: 50_257), (x: 2_000, y: 50_000)])
        let result = simplifier.simplify([dropped, kept], pointBudget: 5)
        XCTAssertEqual(result[0], [dropped[0], dropped[2]])
        XCTAssertEqual(result[1], kept)
    }

    /// 許容誤差の初期値が正の有限値でない時は、等間隔の間引きだけになります。
    ///
    /// 責務: 0・負・NaN・無限大のそれぞれで、一直線の点が等間隔に残り、合計が上限以下になることを確認します。
    func testInvalidInitialToleranceFallsBackToEvenThinning() {
        for initial in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            assertEvenThinning(with: GeoPolylineSimplifier(initialToleranceMeters: initial), label: "初期値 \(initial)")
        }
    }

    /// 許容誤差の上限が正の有限値でない時は、等間隔の間引きだけになります。
    ///
    /// 責務: 0・負・NaN・無限大のそれぞれで、一直線の点が等間隔に残り、合計が上限以下になることを確認します。
    func testInvalidMaximumToleranceFallsBackToEvenThinning() {
        for maximum in [0, -1, Double.nan, Double.infinity] {
            assertEvenThinning(with: GeoPolylineSimplifier(maximumToleranceMeters: maximum), label: "上限 \(maximum)")
        }
    }

    /// 責務: 一直線の2本(100点と50点)を上限 20 で間引き、誤差による間引きでなく等間隔の間引きになっていることを確かめます。
    private func assertEvenThinning(with custom: GeoPolylineSimplifier, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let long = straight(count: 100, step: 10, baseY: 0)
        let short = straight(count: 50, step: 10, baseY: 5_000)
        let result = custom.simplify([long, short], pointBudget: 20)
        XCTAssertEqual(result.count, 2, label, file: file, line: line)
        XCTAssertLessThanOrEqual(total(result), 20, label, file: file, line: line)
        XCTAssertGreaterThan(result[0].count, 2, "一直線でも2点へ畳まれない: \(label)", file: file, line: line)
        XCTAssertGreaterThan(result[1].count, 2, "一直線でも2点へ畳まれない: \(label)", file: file, line: line)
        assertEvenlyThinned(result[0], from: long, file: file, line: line)
        assertEvenlyThinned(result[1], from: short, file: file, line: line)
    }

    /// 初期値が極端に小さくても止まり、上限以下になります。
    ///
    /// 責務: 初期値 1e-300 でジグザグを間引き、時間内に終わって端点が残ることを確認します。
    func testTinyInitialToleranceStillTerminatesWithinBudget() {
        executionTimeAllowance = 30
        let line = GeoPolylineFixtures.zigzag(count: 200, step: 5, amplitude: 40)
        let started = Date()
        let result = GeoPolylineSimplifier(initialToleranceMeters: 1e-300).simplify([line], pointBudget: 50)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "止まらない")
        XCTAssertLessThanOrEqual(total(result), 50)
        XCTAssertEqual(result.first?.first, line.first)
        XCTAssertEqual(result.first?.last, line.last)
    }

    /// 5万点でも、許容誤差が不正な等間隔の間引きだけで時間内に終わります。
    ///
    /// 責務: 5万点の一直線を上限 1,000 で間引き、5 秒以内・上限以下・端点が残ることを確認します。
    func testFiftyThousandPointsWithInvalidToleranceFinishInTime() {
        executionTimeAllowance = 30
        let line = straight(count: 50_000, step: 1, baseY: 0)
        let started = Date()
        let result = GeoPolylineSimplifier(initialToleranceMeters: .nan).simplify([line], pointBudget: 1_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "5万点の間引きが時間内に終わりません")
        XCTAssertLessThanOrEqual(total(result), 1_000)
        assertEvenlyThinned(result[0], from: line)
    }

    /// 5万点でも、上限 0 なら時間内に端点だけを返します。
    ///
    /// 責務: 5万点のジグザグを上限 0 で間引き、5 秒以内に端点2つになることを確認します。
    func testFiftyThousandPointsWithZeroBudgetFinishInTime() {
        executionTimeAllowance = 30
        let line = GeoPolylineFixtures.zigzag(count: 50_000, step: 1, amplitude: 1_000)
        let started = Date()
        let result = simplifier.simplify([line], pointBudget: 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "5万点の間引きが時間内に終わりません")
        assertEndpointsOnly(result, of: [line])
    }
}
