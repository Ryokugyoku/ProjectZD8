import XCTest
@testable import ProjectZD8

/// `GeoPolylineSimplifier` が5万点でも時間内に上限以下へ間引くことを検証します。
@MainActor
final class GeoPolylineSimplifierPerformanceTests: XCTestCase {
    private let simplifier = GeoPolylineSimplifier()

    /// 責務: 折れ線の合計の点数を返します。
    private func total(_ polylines: [[GeoCoordinate]]) -> Int {
        polylines.reduce(0) { $0 + $1.count }
    }

    /// 責務: 結果の折れ線が、元の折れ線の端点を残し、2点以上であることを確かめます。
    private func assertKeepsEndpoints(_ result: [[GeoCoordinate]], of input: [[GeoCoordinate]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.count, input.count, file: file, line: line)
        for (output, source) in zip(result, input) {
            XCTAssertEqual(output.first, source.first, file: file, line: line)
            XCTAssertEqual(output.last, source.last, file: file, line: line)
            XCTAssertGreaterThanOrEqual(output.count, 2, file: file, line: line)
        }
    }

    /// 責務: 5万点のジグザグが、時間内(5 s)に上限以下へ間引かれ、端点と順序が保たれることを確かめます。
    func testFiftyThousandPointZigzagFinishesInTimeWithinBudget() {
        executionTimeAllowance = 30
        let line = GeoPolylineFixtures.zigzag(count: 50_000, step: 1, amplitude: 20)
        let started = Date()
        let result = simplifier.simplify([line], pointBudget: 5_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "5万点の間引きが時間内に終わりません")
        XCTAssertLessThanOrEqual(total(result), 5_000)
        assertKeepsEndpoints(result, of: [line])
    }

    /// 責務: 5万点の大きなジグザグ(256 m でも残る)が、時間内(5 s)に上限以下へ間引かれることを確かめます。
    func testFiftyThousandPointLargeZigzagFinishesInTime() {
        executionTimeAllowance = 30
        let line = GeoPolylineFixtures.zigzag(count: 50_000, step: 10, amplitude: 1_000)
        let started = Date()
        let result = simplifier.simplify([line], pointBudget: 1_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "5万点の間引きが時間内に終わりません")
        XCTAssertLessThanOrEqual(total(result), 1_000)
        assertKeepsEndpoints(result, of: [line])
    }
}
