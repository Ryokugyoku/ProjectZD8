import XCTest
@testable import ProjectZD8

/// analysis-derive.js の派生チャンネルを検証します。
final class AnalysisDeriveTests: XCTestCase {
    /// 責務: 車速の直線的な増加から、一定の加速度(m/s²)が得られることを確認します。
    func testAccelerationFromSpeed() throws {
        let values: [Double] = try AnalysisWebScriptRunner.evaluate("""
            const t = Float64Array.from({length: 11}, (_, i) => i);
            const v = t.map((x) => x * 3.6);   // 3.6 km/h per second = 1 m/s^2
            return Array.from(accelerationFromSpeed(t, v).values);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertFalse(values.isEmpty)
        for v in values { XCTAssertEqual(v, 1, accuracy: 1e-9) }
    }

    /// 責務: 近傍に隣接サンプルが無い点(長い欠測の前後)は加速度を出さないことを確認します。
    func testAccelerationSkipsGaps() throws {
        let times: [Double] = try AnalysisWebScriptRunner.evaluate("""
            const t = Float64Array.from([0, 1, 2, 3, 20, 21, 22, 23]);
            return Array.from(accelerationFromSpeed(t, t.map((x) => x), 1, 3).times);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertFalse(times.contains(3), "3秒の次は17秒後なので勾配を作らない")
        XCTAssertFalse(times.contains(20))
    }

    /// 責務: 回転数/車速の比から、ギアが自動でクラスタリングされることを確認します。
    func testGearClustering() throws {
        struct Result: Decodable { let gears: [Gear]; let assigned: [Int] }
        struct Gear: Decodable { let gear: Int; let ratio: Double; let count: Int }
        let r: Result = try AnalysisWebScriptRunner.evaluate("""
            const ratios = [];
            const centres = [70, 47, 36];
            let k = 0;
            for (const c of centres) for (let i = 0; i < 100; i++) ratios.push(c * (1 + (((k++ * 7919) % 21) - 10) / 1000));
            const out = clusterGears(Float64Array.from(ratios));
            return { gears: out.gears, assigned: [out.assignment[0], out.assignment[150], out.assignment[250]] };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.gears.map(\.gear), [1, 2, 3], "比が大きい順に1速から")
        XCTAssertEqual(r.gears[0].ratio, 70, accuracy: 1)
        XCTAssertEqual(r.gears[1].ratio, 47, accuracy: 1)
        XCTAssertEqual(r.gears[2].ratio, 36, accuracy: 1)
        XCTAssertEqual(r.assigned, [1, 2, 3])
    }

    /// 責務: 回転数/車速の比は、停車中(低速)を含めず、車速を近い時刻で結合することを確認します。
    func testRpmSpeedRatioIgnoresStanding() throws {
        struct Ratio: Decodable { let times: [Double]; let values: [Double] }
        let r: Ratio = try AnalysisWebScriptRunner.evaluate("""
            const rpm = { times: [0, 1, 2], values: [800, 2000, 3000] };
            const speed = { times: [0, 1, 2], values: [0, 50, 100] };
            const out = rpmSpeedRatio(rpm, speed);
            return { times: Array.from(out.times), values: Array.from(out.values) };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.times, [1, 2])
        XCTAssertEqual(r.values, [40, 30])
    }

    /// 責務: 燃料補正の合計は、相手が無い時刻を出力しないことを確認します。
    func testFuelTrimSum() throws {
        struct Sum: Decodable { let times: [Double]; let values: [Double] }
        let r: Sum = try AnalysisWebScriptRunner.evaluate("""
            const out = fuelTrimSum({ times: [0, 1, 10], values: [1, 2, 3] }, { times: [0.2, 1.1], values: [10, 20] }, 0.5);
            return { times: Array.from(out.times), values: Array.from(out.values) };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.times, [0, 1])
        XCTAssertEqual(r.values, [11, 22])
    }

    /// 責務: 式から派生チャンネルを作れること、未知の参照・欠測の伝播を確認します。
    func testDeriveFromExpression() throws {
        struct Derived: Decodable { let times: [Double]; let values: [Double] }
        let ctx = try AnalysisWebScriptRunner.makeContext()
        let r: Derived = try AnalysisWebScriptRunner.evaluate("""
            const channels = [
              { id: '01-0C', name: 'Engine speed', times: [0, 1, 2], values: [1000, 2000, 3000] },
              { id: '01-0D', name: 'Vehicle speed', times: [0.1, 1.1], values: [10, 20] }];
            const out = deriveFromExpression('rpm / speed + [Vehicle speed] * 0', channels, 0.3);
            return { times: Array.from(out.times), values: Array.from(out.values) };
        """, in: ctx)
        XCTAssertEqual(r.times, [0, 1], "速度の無い時刻(2秒)は出力しない")
        XCTAssertEqual(r.values, [100, 100])
        let code: String = try AnalysisWebScriptRunner.evaluate("try { deriveFromExpression('rpm + nothing', [{ id: '01-0C', name: 'x', times: [0], values: [1] }]); return 'ok'; } catch (e) { return e.code; }", in: ctx)
        XCTAssertEqual(code, "unknownReference")
        let noRef: String = try AnalysisWebScriptRunner.evaluate("try { deriveFromExpression('1 + 2', []); return 'ok'; } catch (e) { return e.code; }", in: ctx)
        XCTAssertEqual(noRef, "noReference")
    }
}
