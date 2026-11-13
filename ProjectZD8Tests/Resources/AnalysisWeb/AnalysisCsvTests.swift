import XCTest
@testable import ProjectZD8

/// analysis-csv.js のCSV出力を検証します。
final class AnalysisCsvTests: XCTestCase {
    /// 責務: 欠測は空欄で、0や補間値を入れないことを確認します。
    func testMissingValuesAreEmptyCells() throws {
        let csv: String = try AnalysisWebScriptRunner.evaluate("""
            return buildCsv([
              { name: 'Speed', unit: 'km/h', times: [0, 1, 2], values: [10, 0, 30] },
              { name: 'Coolant', unit: '°C', times: [1], values: [88.5] }]);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(csv, "time_s,Speed [km/h],Coolant [°C]\n0,10,\n1,0,88.5\n2,30,\n")
    }

    /// 責務: 時間範囲で絞ること、カンマ・引用符を含む名前を引用することを確認します。
    func testRangeAndQuoting() throws {
        let csv: String = try AnalysisWebScriptRunner.evaluate("""
            return buildCsv([{ name: 'A, "x"', unit: '', times: [0, 1, 2, 3], values: [1, 2, 3, 4] }], 1, 2);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(csv, "time_s,\"A, \"\"x\"\"\"\n1,2\n2,3\n")
    }
}
