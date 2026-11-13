import XCTest
@testable import ProjectZD8

/// analysis-decimate.js の間引きと途切れ検出を検証します。
final class AnalysisDecimateTests: XCTestCase {
    private struct Result: Decodable { let count: Int; let decimated: Bool; let hasSpike: Bool; let hasDip: Bool; let sortedTimes: Bool }

    /// 責務: 10万点を間引いても、孤立した最大・最小が残り、時刻順が保たれることを確認します。
    func testKeepsExtremesAndOrder() throws {
        let r: Result = try AnalysisWebScriptRunner.evaluate("""
            const n = 100000; const t = new Float64Array(n); const v = new Float64Array(n);
            for (let i = 0; i < n; i++) { t[i] = i * 0.01; v[i] = Math.sin(i / 300); }
            v[54321] = 9; v[77777] = -9;
            const d = minMaxDecimate(t, v, 0, t[n - 1], 500);
            let sorted = true; for (let i = 1; i < d.count; i++) if (d.x[i] < d.x[i - 1]) sorted = false;
            return { count: d.count, decimated: d.decimated, hasSpike: Array.from(d.y).includes(9), hasDip: Array.from(d.y).includes(-9), sortedTimes: sorted };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertTrue(r.decimated)
        XCTAssertLessThanOrEqual(r.count, 2_100)
        XCTAssertTrue(r.hasSpike)
        XCTAssertTrue(r.hasDip)
        XCTAssertTrue(r.sortedTimes)
    }

    /// 責務: 短い窓は間引かず、窓の外側の1点を含めて返すことを確認します。
    func testShortWindowReturnsRawPointsWithNeighbours() throws {
        struct Raw: Decodable { let count: Int; let decimated: Bool; let first: Double; let last: Double }
        let r: Raw = try AnalysisWebScriptRunner.evaluate("""
            const t = Float64Array.from({length: 100}, (_, i) => i); const v = t.map((x) => x * 2);
            const d = minMaxDecimate(t, v, 10, 20, 500);
            return { count: d.count, decimated: d.decimated, first: d.x[0], last: d.x[d.count - 1] };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertFalse(r.decimated)
        XCTAssertEqual(r.count, 13)
        XCTAssertEqual(r.first, 9)
        XCTAssertEqual(r.last, 21)
    }

    /// 責務: 時刻の途切れを検出し、間引き後の2点間に途切れがあるかを判定できることを確認します。
    func testGapDetection() throws {
        struct Gaps: Decodable { let indices: [Int]; let across: Bool; let before: Bool }
        let r: Gaps = try AnalysisWebScriptRunner.evaluate("""
            const t = [0, 1, 2, 10, 11, 12];
            const g = findGaps(t, 3);
            return { indices: Array.from(g), across: hasGapBetween(g, 0, 5), before: hasGapBetween(g, 0, 2) };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.indices, [2])
        XCTAssertTrue(r.across)
        XCTAssertFalse(r.before)
    }

    /// 責務: 欠測(NaN)を値域へ含めないことを確認します。
    func testVisibleRangeIgnoresMissing() throws {
        struct Range: Decodable { let min: Double; let max: Double }
        let r: Range = try AnalysisWebScriptRunner.evaluate("return visibleRange([0,1,2,3],[5,NaN,1,9], 0, 2);", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.min, 1); XCTAssertEqual(r.max, 5)
    }
}
