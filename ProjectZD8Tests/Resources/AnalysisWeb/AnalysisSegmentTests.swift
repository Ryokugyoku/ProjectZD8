import XCTest
@testable import ProjectZD8

/// analysis-segment.js の走行区間の分割とイベント検出を検証します。
final class AnalysisSegmentTests: XCTestCase {
    private struct Segment: Decodable { let type: String; let t0: Double; let t1: Double }

    /// 停止10秒→8秒で加速→60km/hで巡航20秒→8秒で減速→停止10秒の1Hz速度を作るスクリプトです。
    private let profile = """
        const speed = { times: [], values: [] };
        const rpm = { times: [], values: [] };
        const push = (t, v) => { speed.times.push(t); speed.values.push(v); rpm.times.push(t); rpm.values.push(v > 0 ? 2000 : 800); };
        let t = 0;
        for (let i = 0; i < 10; i++) push(t++, 0);
        for (let i = 1; i <= 8; i++) push(t++, i * 7.5);
        for (let i = 0; i < 20; i++) push(t++, 60);
        for (let i = 1; i <= 8; i++) push(t++, 60 - i * 7.5);
        for (let i = 0; i < 10; i++) push(t++, 0);
    """

    /// 責務: エンジン稼働中の停止はアイドル、加速・巡航・減速が順に検出されることを確認します。
    func testSegmentsInOrder() throws {
        let segments: [Segment] = try AnalysisWebScriptRunner.evaluate("\(profile) return segmentDrive(speed, rpm);", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(segments.map(\.type), ["idle", "acceleration", "cruise", "deceleration", "idle"])
        for (a, b) in zip(segments, segments.dropFirst()) { XCTAssertLessThanOrEqual(a.t1, b.t0 + 1e-9) }
        let cruise = try XCTUnwrap(segments.first { $0.type == "cruise" })
        XCTAssertEqual(cruise.t1 - cruise.t0, 20, accuracy: 4)
    }

    /// 責務: 回転数が無い(またはエンジン停止)の停止は「停止」になることを確認します。
    func testStandingWithoutEngineIsStop() throws {
        let types: [String] = try AnalysisWebScriptRunner.evaluate("""
            const speed = { times: Array.from({length: 20}, (_, i) => i), values: new Array(20).fill(0) };
            return segmentDrive(speed, null).map((s) => s.type);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(types, ["stop"])
    }

    /// 責務: サンプルが途切れた区間は、補間せず区間から除外されることを確認します。
    func testGapIsNotInterpolated() throws {
        let segments: [Segment] = try AnalysisWebScriptRunner.evaluate("""
            const times = [...Array.from({length: 20}, (_, i) => i), ...Array.from({length: 20}, (_, i) => 60 + i)];
            const speed = { times, values: times.map(() => 50) };
            return segmentDrive(speed, null);
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertFalse(segments.contains { $0.t0 < 40 && $0.t1 > 25 }, "19〜60秒は欠測なので区間にしない")
        XCTAssertEqual(segments.count, 2)
    }

    /// 責務: 時刻から区間タイプを引けることを確認します。
    func testSegmentTypeAt() throws {
        let r: [String?] = try AnalysisWebScriptRunner.evaluate("const s=[{type:'idle',t0:0,t1:10},{type:'cruise',t0:10,t1:30}]; return [segmentTypeAt(s,5), segmentTypeAt(s,10), segmentTypeAt(s,30), segmentTypeAt(s,-1)];", in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r, ["idle", "cruise", nil, nil])
    }

    private struct Event: Decodable { let type: String; let t: Double; let value: Double }

    /// 責務: 急加速・急減速・高水温・燃料補正の逸脱・回転数ピークを検出することを確認します。
    func testDetectEvents() throws {
        let events: [Event] = try AnalysisWebScriptRunner.evaluate("""
            const speed = { times: [], values: [] };
            const add = (t, v) => { speed.times.push(t); speed.values.push(v); };
            for (let i = 0; i < 10; i++) add(i, 0);
            for (let i = 1; i <= 4; i++) add(9 + i, i * 15);   // 0 to 60 in 4 s = 4.2 m/s^2
            for (let i = 0; i < 10; i++) add(14 + i, 60);
            for (let i = 1; i <= 3; i++) add(23 + i, 60 - i * 20); // 60 to 0 in 3 s = 5.6 m/s^2
            const coolant = { id: '01-05', times: [0, 1, 2, 3, 4], values: [90, 107, 110, 106, 95] };
            const stft = { id: '01-06', times: [0, 1, 2, 3, 4, 5], values: [0, 25, 30, 26, 0, 0] };
            return detectEvents({ speed, coolant, stft });
        """, in: AnalysisWebScriptRunner.makeContext())
        let types = Set(events.map(\.type))
        XCTAssertTrue(types.isSuperset(of: ["hardAcceleration", "hardBraking", "highCoolant", "fuelTrimExcursion"]), "\(types)")
        XCTAssertEqual(try XCTUnwrap(events.first { $0.type == "highCoolant" }).value, 110)
        XCTAssertEqual(try XCTUnwrap(events.first { $0.type == "fuelTrimExcursion" }).value, 30)
        XCTAssertTrue(events.map(\.t) == events.map(\.t).sorted())
    }

    /// 責務: 穏やかな運転では急加速・急減速を検出しないことを確認します。
    func testGentleDrivingHasNoHardEvents() throws {
        let events: [Event] = try AnalysisWebScriptRunner.evaluate("""
            const times = Array.from({length: 60}, (_, i) => i);
            return detectEvents({ speed: { times, values: times.map((t) => Math.min(t, 40)) } });
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertTrue(events.isEmpty)
    }
}
