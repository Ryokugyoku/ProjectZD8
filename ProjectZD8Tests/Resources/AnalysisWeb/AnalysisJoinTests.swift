import XCTest
@testable import ProjectZD8

/// analysis-join.js の最近傍結合を検証します。
final class AnalysisJoinTests: XCTestCase {
    /// 責務: 許容差を超える対応は欠測(NaN)のままで、補間しないことを確認します。
    func testAlignNearestRespectsTolerance() throws {
        let r: [Double?] = try AnalysisWebScriptRunner.evaluate("return Array.from(alignNearest([0,1,2,3], [0.1, 2.05], [10, 20], 0.2), (v) => Number.isNaN(v) ? null : v);", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r, [10, nil, 20, nil])
    }

    /// 責務: 結合で相手の無いA側の点が落ちること、近い方が選ばれることを確認します。
    func testNearestJoinDropsUnmatched() throws {
        struct Joined: Decodable { let t: [Double]; let a: [Double]; let b: [Double]; let n: Int }
        let r: Joined = try AnalysisWebScriptRunner.evaluate("const j = nearestJoin([0, 1, 2, 10], [1, 2, 3, 4], [0.4, 1.8], [100, 200], 0.5); return { t: Array.from(j.t), a: Array.from(j.a), b: Array.from(j.b), n: j.n };", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.t, [0, 2], "t=1は最寄りの0.4秒でも0.6秒離れ、許容差0.5秒を超えるため落ちる")
        XCTAssertEqual(r.a, [1, 3])
        XCTAssertEqual(r.b, [100, 200])
    }

    /// 責務: 3チャンネル結合で、Zの欠測はNaNのまま残りX・Yの組は残ることを確認します。
    func testJoinXYZKeepsMissingColour() throws {
        struct Joined: Decodable { let n: Int; let x: [Double]; let y: [Double]; let zMissing: [Bool] }
        let r: Joined = try AnalysisWebScriptRunner.evaluate("""
            const x = { times: [0, 1, 2], values: [1, 2, 3] }, y = { times: [0, 1, 2], values: [10, 20, 30] }, z = { times: [0], values: [5] };
            const j = joinXYZ(x, y, z, 0.1);
            return { n: j.n, x: Array.from(j.x), y: Array.from(j.y), zMissing: Array.from(j.z, (v) => Number.isNaN(v)) };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.n, 3)
        XCTAssertEqual(r.zMissing, [false, true, true])
    }

    /// 責務: 時間重みが次の点までの間隔で、欠測区間を跨いでは上限で打ち切られることを確認します。
    func testSampleWeightsCapAcrossGaps() throws {
        let r: [Double] = try AnalysisWebScriptRunner.evaluate("return Array.from(sampleWeights([0, 1, 2, 3, 100]));", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r, [1, 1, 1, 2, 1])
    }
}
