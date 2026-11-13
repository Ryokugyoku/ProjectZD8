import XCTest
@testable import ProjectZD8

/// analysis-model.js と、Swiftが出力するデータセット・長期傾向JSONとの契約を検証します。
final class AnalysisModelScriptTests: XCTestCase {
    private typealias F = AnalysisFixtures

    private struct Read: Decodable { let channels: [String]; let speedValues: [Double]; let rpmMax: Double; let maintenanceT: Double; let quality: Int; let duration: Double; let startedAtMs: Double; let coolantUnused: Bool }

    private struct Built: Decodable {
        let channelCount: Int
        let segmentTypes: [String]
        let eventTypes: [String]
        let derivedIDs: [String]
        let errors: [String]
        let maintenanceOffsets: [Double]
    }

    /// 責務: デモデータで区間・イベントが検出され、派生チャンネルを作れることを確認します。
    func testBuildSessionFromDemoDataset() throws {
        let r: Built = try AnalysisWebScriptRunner.evaluate("""
            const session = buildSession(buildDemoDataset({ lang: 'en' }));
            session.derivedDefs = [{ kind: 'builtin', key: 'accel' }, { kind: 'builtin', key: 'gear' }, { kind: 'builtin', key: 'trimsum' }, { kind: 'expression', id: 'd-x1', name: 'X', unit: '', source: 'rpm / (speed + 1)', tolerance: 1 }];
            const errors = rebuildDerived(session, (k) => k);
            return { channelCount: session.channels.size, segmentTypes: Array.from(new Set(session.segments.map((s) => s.type))),
              eventTypes: Array.from(new Set(session.events.map((e) => e.type))), derivedIDs: Array.from(session.channels.values()).filter((c) => c.derived).map((c) => c.id),
              errors: Object.keys(errors), maintenanceOffsets: session.maintenance.map((m) => m.t) };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(r.channelCount, 10 + 4)
        XCTAssertTrue(Set(r.segmentTypes).isSuperset(of: ["idle", "acceleration", "cruise", "deceleration"]), "\(r.segmentTypes)")
        XCTAssertTrue(Set(r.eventTypes).isSuperset(of: ["hardAcceleration", "hardBraking", "fuelTrimExcursion"]), "\(r.eventTypes)")
        XCTAssertEqual(Set(r.derivedIDs), ["d-accel", "d-gear", "d-trimsum", "d-x1"])
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertLessThan(try XCTUnwrap(r.maintenanceOffsets.first), 0, "整備はセッション開始より前")
    }

    /// 責務: 新しすぎる形式のデータセットは型付きの失敗として拒否することを確認します。
    func testRejectsUnknownSchemaVersion() throws {
        let code: String = try AnalysisWebScriptRunner.evaluate("""
            const d = buildDemoDataset({}); d.schemaVersion = 99;
            try { buildSession(d); return 'ok'; } catch (e) { return e.code; }
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(code, "schemaVersion")
    }

    /// 責務: Swiftが符号化したデータセットを、そのままWebのモデルが読めることを確認します(形式の契約)。
    func testSwiftDatasetJSONIsReadableByTheWebModel() async throws {
        let vehicle = F.vehicle()
        let sessions = AnalysisFakeSessionRepository()
        let record = MaintenanceRecord(vehicleID: vehicle.id, kind: .light, title: "Oil", performedAt: Date(timeIntervalSince1970: 1_000_000 - 86_400), odometerKilometers: 999)
        let useCase = BuildAnalysisDatasetUseCase(
            decoder: AnalysisSessionDecoder(sessions: sessions),
            vehicles: AnalysisFakeVehicleRepository([vehicle]),
            maintenance: AnalysisFakeMaintenanceRepository([record]),
            names: AnalysisFakeNameResolver()
        )
        let session = F.session(vehicleID: vehicle.id, duration: 30, sampleCount: 6)
        let pids = F.standardPIDs()
        var samples: [SessionSample] = []
        for second in 0..<10 {
            samples.append(F.sample(Int64(samples.count), seconds: Double(second), F.speed, payload: [UInt8(second * 5)]))
            samples.append(F.sample(Int64(samples.count), seconds: Double(second), F.rpm, payload: [0x0F, 0xA0]))
        }
        await sessions.seed(session, pids: pids, samples: samples)
        let dataset = try await useCase.build(sessionID: session.id)
        let json = String(decoding: try await AnalysisJSONEncoder.encode(dataset), as: UTF8.self)

        let r: Read = try AnalysisWebScriptRunner.evaluate("""
            const s = buildSession(JSON.parse(\(Self.jsLiteral(json))));
            const speed = s.channels.get('01-0D');
            return { channels: Array.from(s.channels.keys()), speedValues: Array.from(speed.values), rpmMax: s.channels.get('01-0C').max,
              maintenanceT: s.maintenance[0].t, quality: speed.quality.responded, duration: s.durationSeconds, startedAtMs: s.startedAtMs, coolantUnused: !s.channels.has('01-05') };
        """, in: AnalysisWebScriptRunner.makeContext())
        XCTAssertEqual(Set(r.channels), ["01-0C", "01-0D"], "要求の無かったチャンネルは含まれない")
        XCTAssertEqual(r.speedValues, (0..<10).map { Double($0 * 5) })
        XCTAssertEqual(r.rpmMax, 1000)
        XCTAssertEqual(r.maintenanceT, -86_400, accuracy: 0.001)
        XCTAssertEqual(r.quality, 10)
        XCTAssertEqual(r.duration, 30)
        XCTAssertEqual(r.startedAtMs, 1_000_000_000)
        XCTAssertTrue(r.coolantUnused)
    }

    /// 責務: 長期傾向のJSONが、Webの長期傾向ビューが読む項目を全て持つことを確認します。
    func testTrendJSONHasTheFieldsTheViewReads() async throws {
        let vehicle = F.vehicle()
        let sessions = AnalysisFakeSessionRepository()
        let useCase = BuildVehicleTrendDatasetUseCase(
            sessions: sessions,
            decoder: AnalysisSessionDecoder(sessions: sessions),
            vehicles: AnalysisFakeVehicleRepository([vehicle]),
            maintenance: AnalysisFakeMaintenanceRepository([MaintenanceRecord(vehicleID: vehicle.id, kind: .heavy, title: "Plugs", performedAt: Date(timeIntervalSince1970: 5), odometerKilometers: 12)]),
            names: AnalysisFakeNameResolver()
        )
        let session = F.session(vehicleID: vehicle.id, sampleCount: 3)
        await sessions.seed(session, pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)], samples: (0..<3).map { F.sample(Int64($0), seconds: Double($0), F.speed, payload: [50]) })
        let json = try await AnalysisJSONEncoder.encode(try await useCase.build(vehicleID: vehicle.id))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        for key in ["schemaVersion", "vehicle", "channels", "sessions", "maintenance", "skippedCloudOnlySessions", "excludedDemoSessions"] { XCTAssertNotNil(object[key], key) }
        let channel = try XCTUnwrap((object["channels"] as? [[String: Any]])?.first)
        for key in ["id", "name", "unit"] { XCTAssertNotNil(channel[key], key) }
        let trendSession = try XCTUnwrap((object["sessions"] as? [[String: Any]])?.first)
        for key in ["id", "startedAt", "isDemo", "stats", "odometerStartKilometers"] { XCTAssertNotNil(trendSession[key], key) }
        let stat = try XCTUnwrap((trendSession["stats"] as? [[String: Any]])?.first)
        XCTAssertEqual(stat["condition"] as? String, "all")
        for key in ["channelId", "median", "p05", "p95", "count"] { XCTAssertNotNil(stat[key], key) }
        let marker = try XCTUnwrap((object["maintenance"] as? [[String: Any]])?.first)
        for key in ["date", "title", "odometerKilometers", "kind"] { XCTAssertNotNil(marker[key], key) }
    }

    /// 責務: 文字列をJavaScriptの文字列リテラルへ変換します。
    private static func jsLiteral(_ text: String) -> String {
        String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
    }
}
