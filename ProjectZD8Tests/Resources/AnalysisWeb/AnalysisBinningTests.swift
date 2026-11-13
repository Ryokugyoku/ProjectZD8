import XCTest
@testable import ProjectZD8

/// analysis-binning.js の2次元ビン分けを検証します。
final class AnalysisBinningTests: XCTestCase {
    private struct Grid: Decodable { let count: [Double]; let occupancy: [Double]; let mean: [Double?]; let total: Int; let maxOccupancy: Double }

    /// 責務: セルの件数・滞在時間・第3軸の平均が正しいこと、範囲外が無視され、最大値が最後のビンへ入ることを確認します。
    func testBinGrid() throws {
        let g: Grid = try AnalysisWebScriptRunner.evaluate("""
            const grid = binGrid({ xs: [0.5, 0.6, 1.5, 2, 99], ys: [0.5, 0.5, 1.5, 2, 0.5], zs: [10, 20, 30, 40, 50], weights: [1, 1, 2, 3, 4],
              xMin: 0, xMax: 2, yMin: 0, yMax: 2, nx: 2, ny: 2 });
            return { count: Array.from(grid.count), occupancy: Array.from(grid.occupancy), mean: Array.from(grid.mean, (v) => Number.isNaN(v) ? null : v), total: grid.total, maxOccupancy: grid.maxOccupancy };
        """, in: AnalysisWebScriptRunner.makeContext())
        // セル添字 = iy * 2 + ix。(0,0)に2点、(1,1)に2点(1.5,1.5)と(2,2)。
        XCTAssertEqual(g.count, [2, 0, 0, 2])
        XCTAssertEqual(g.occupancy, [2, 0, 0, 5])
        XCTAssertEqual(g.mean[0], 15)
        XCTAssertNil(g.mean[1], "点の無いセルは0でなく欠測")
        XCTAssertEqual(g.mean[3], 35)
        XCTAssertEqual(g.total, 4)
        XCTAssertEqual(g.maxOccupancy, 5)
    }

    /// 責務: セルの境界値を返すことを確認します。
    func testCellBounds() throws {
        let b: [Double] = try AnalysisWebScriptRunner.evaluate("const g = binGrid({xs:[],ys:[],xMin:0,xMax:10,yMin:0,yMax:100,nx:5,ny:4}); const c = cellBounds(g, 1, 2); return [c.x0, c.x1, c.y0, c.y1];", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(b, [2, 4, 50, 75])
    }
}
