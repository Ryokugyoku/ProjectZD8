import JavaScriptCore
import XCTest
@testable import ProjectZD8

/// analysis-stats.js の統計関数を検証します。
final class AnalysisStatsTests: XCTestCase {
    private func context() throws -> JSContext { try AnalysisWebScriptRunner.makeContext() }

    private struct Summary: Decodable { let n: Int; let min: Double?; let max: Double?; let mean: Double?; let median: Double?; let p05: Double?; let p95: Double?; let std: Double?; let slope: Double? }

    /// 責務: 範囲統計(n・最小・最大・平均・中央値・分位・標準偏差・傾き)が正しいことを確認します。
    func testSummarize() throws {
        let s: Summary = try AnalysisWebScriptRunner.evaluate("return summarize([0,1,2,3,4],[1,2,3,4,5]);", in: context())
        XCTAssertEqual(s.n, 5)
        XCTAssertEqual(s.min, 1); XCTAssertEqual(s.max, 5); XCTAssertEqual(s.mean, 3); XCTAssertEqual(s.median, 3)
        XCTAssertEqual(try XCTUnwrap(s.p05), 1.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.p95), 4.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.std), 2.5.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.slope), 1, accuracy: 1e-9)
    }

    /// 責務: 窓で絞ること、欠測(NaN)を無視すること、空の窓がNaNになることを確認します。
    func testSummarizeWindowAndMissing() throws {
        let ctx = try context()
        let windowed: Summary = try AnalysisWebScriptRunner.evaluate("return summarize([0,1,2,3,4],[1,NaN,3,4,5], 1, 3);", in: ctx)
        XCTAssertEqual(windowed.n, 2, "NaNは数えない")
        XCTAssertEqual(windowed.mean, 3.5)
        let empty: Summary = try AnalysisWebScriptRunner.evaluate("return summarize([0,1],[1,2], 10, 20);", in: ctx)
        XCTAssertEqual(empty.n, 0)
        XCTAssertNil(empty.mean, "空の窓は0でなくNaN(JSONではnull)")
    }

    /// 責務: 線形回帰の傾き・切片・決定係数を確認します。
    func testLinearRegression() throws {
        struct Reg: Decodable { let slope: Double; let intercept: Double; let r2: Double; let n: Int }
        let exact: Reg = try AnalysisWebScriptRunner.evaluate("return linearRegression([0,1,2,3],[1,3,5,7]);", in: context())
        XCTAssertEqual(exact.slope, 2, accuracy: 1e-12); XCTAssertEqual(exact.intercept, 1, accuracy: 1e-12); XCTAssertEqual(exact.r2, 1, accuracy: 1e-12)
        let noisy: Reg = try AnalysisWebScriptRunner.evaluate("return linearRegression([0,1,2,3],[0,1,0,1]);", in: context())
        XCTAssertEqual(noisy.r2, 0.2, accuracy: 1e-12)
    }

    /// 責務: ヒストグラムのビン割当と、最大値が最後のビンへ入ることを確認します。
    func testHistogram() throws {
        struct Hist: Decodable { let counts: [Double]; let total: Int; let min: Double; let max: Double }
        let h: Hist = try AnalysisWebScriptRunner.evaluate("const h = histogram([0,1,2,3,4,5,10], {bins: 5, min: 0, max: 10}); return { counts: Array.from(h.counts), total: h.total, min: h.min, max: h.max };", in: context())
        XCTAssertEqual(h.counts, [2, 2, 2, 0, 1])
        XCTAssertEqual(h.total, 7)
    }

    /// 責務: 箱ひげ図の四分位・ひげ・外れ値を確認します。
    func testBoxStats() throws {
        struct Box: Decodable { let q1: Double; let median: Double; let q3: Double; let highWhisker: Double; let outliers: Int }
        let b: Box = try AnalysisWebScriptRunner.evaluate("return boxStats([1,2,3,4,5,6,7,8,9,100]);", in: context())
        XCTAssertEqual(b.median, 5.5); XCTAssertEqual(b.q1, 3.25, accuracy: 1e-9); XCTAssertEqual(b.q3, 7.75, accuracy: 1e-9)
        XCTAssertEqual(b.outliers, 1); XCTAssertEqual(b.highWhisker, 9)
    }

    /// 責務: 二分探索と最近傍の探索、見やすい目盛りを確認します。
    func testSearchAndTicks() throws {
        let ctx = try context()
        let found: [Int] = try AnalysisWebScriptRunner.evaluate("const t=[0,1,2,2,3]; return [lowerBound(t,2), upperBound(t,2), nearestIndex(t,2.9), nearestIndex([],1)];", in: ctx)
        XCTAssertEqual(found, [2, 4, 4, -1])
        let ticks: [Double] = try AnalysisWebScriptRunner.evaluate("return niceTicks(0, 100, 5);", in: ctx)
        XCTAssertEqual(ticks, [0, 20, 40, 60, 80, 100])
        let medianInterval: Double = try AnalysisWebScriptRunner.evaluate("return medianInterval([0,0.1,0.2,0.3,5]);", in: ctx)
        XCTAssertEqual(medianInterval, 0.1, accuracy: 1e-9)
    }
}
