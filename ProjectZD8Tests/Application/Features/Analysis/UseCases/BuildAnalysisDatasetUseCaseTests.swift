import XCTest
@testable import ProjectZD8

/// 分析データセットの組み立てを検証します。
final class BuildAnalysisDatasetUseCaseTests: XCTestCase {
    private typealias F = AnalysisFixtures

    /// 責務: 検証用のユースケースとリポジトリ一式を作ります。
    private func makeSUT(pageSize: Int = 5_000, vehicle: Vehicle = F.vehicle(), records: [MaintenanceRecord] = []) -> (BuildAnalysisDatasetUseCase, AnalysisFakeSessionRepository) {
        let sessions = AnalysisFakeSessionRepository()
        let decoder = AnalysisSessionDecoder(sessions: sessions, pageSize: pageSize)
        let useCase = BuildAnalysisDatasetUseCase(
            decoder: decoder,
            vehicles: AnalysisFakeVehicleRepository([vehicle]),
            maintenance: AnalysisFakeMaintenanceRepository(records),
            names: AnalysisFakeNameResolver()
        )
        return (useCase, sessions)
    }

    /// 責務: 取得時のスナップショットで変換し、現行カタログの式を使わないことを確認します。
    func testDecodesWithSessionSnapshotFormulaNotCurrentCatalog() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, sampleCount: 1)
        // カタログの車速式は "A"。スナップショットは "A * 2"(別改訂)。
        let pids = [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A * 2", unit: "km/h", min: 0, max: 255, revision: 7)]
        await sessions.seed(session, pids: pids, samples: [F.sample(0, seconds: 1.5, F.speed, payload: [40])])

        let dataset = try await useCase.build(sessionID: session.id)

        let channel = try XCTUnwrap(dataset.channels.first)
        XCTAssertEqual(channel.values, [80])
        XCTAssertEqual(channel.times, [1.5])
        XCTAssertEqual(channel.definitionRevision, 7)
        XCTAssertEqual(channel.id, "01-0D")
        XCTAssertEqual(channel.name, "name:obd.pid.01.0D.name")
        XCTAssertEqual(channel.unit, "km/h")
    }

    /// 責務: 無応答・範囲外・変換不能は値に含めず、件数だけ数えることを確認します。
    func testMissingStaysMissingAndQualityCounts() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, sampleCount: 8)
        let pids = [
            F.pid(F.rpm, ordinal: 0, bytes: 2, formula: "(A * 256 + B) / 4", unit: "rpm", min: 0, max: 16_383.75),
            F.pid(F.speed, ordinal: 1, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 200)
        ]
        let samples = [
            F.sample(0, seconds: 0.0, F.rpm, payload: [0x0F, 0xA0]),   // 1000 rpm
            F.sample(1, seconds: 0.1, F.rpm, .timedOut),
            F.sample(2, seconds: 0.2, F.rpm, .noData),
            F.sample(3, seconds: 0.3, F.rpm, .failed),
            F.sample(4, seconds: 0.4, F.rpm, payload: [0x0F]),          // バイト不足
            F.sample(5, seconds: 0.5, F.speed, payload: [250]),         // 範囲外(最大200)
            F.sample(6, seconds: 0.6, F.speed, payload: [0]),           // 0 km/h は有効な実測値
            F.sample(7, seconds: 0.7, F.rpm, payload: [0x1F, 0x40])     // 2000 rpm
        ]
        await sessions.seed(session, pids: pids, samples: samples)

        let dataset = try await useCase.build(sessionID: session.id)

        let rpm = try XCTUnwrap(dataset.channels.first { $0.id == "01-0C" })
        XCTAssertEqual(rpm.values, [1000, 2000])
        XCTAssertEqual(rpm.times, [0.0, 0.7])
        XCTAssertEqual(rpm.quality, AnalysisChannelQuality(requested: 6, responded: 3, noData: 1, timedOut: 1, failed: 1, decoded: 2, undecodable: 1, outOfRange: 0))
        let speed = try XCTUnwrap(dataset.channels.first { $0.id == "01-0D" })
        XCTAssertEqual(speed.values, [0], "0は欠測ではなく実測値として残る")
        XCTAssertEqual(speed.quality.outOfRange, 1)
        XCTAssertEqual(speed.quality.responded, 2)
        XCTAssertEqual(speed.quality.decoded, 1)
    }

    /// 責務: サンプルを指定ページ幅で複数回に分けて読み出すことを確認します。
    func testPagesThroughSamples() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(pageSize: 2, vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, sampleCount: 7)
        let pids = [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)]
        let samples = (0..<7).map { F.sample(Int64($0), seconds: Double($0), F.speed, payload: [UInt8($0)]) }
        await sessions.seed(session, pids: pids, samples: samples)

        let dataset = try await useCase.build(sessionID: session.id)

        XCTAssertEqual(dataset.channels[0].values, [0, 1, 2, 3, 4, 5, 6])
        let requests = await sessions.samplePageRequests
        XCTAssertEqual(requests, 4)
    }

    /// 責務: 応答の途切れを欠測区間として報告することを確認します。
    func testReportsGaps() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, duration: 100, sampleCount: 3)
        let pids = [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)]
        let samples = [
            F.sample(0, seconds: 0.5, F.speed, payload: [1]),
            F.sample(1, seconds: 1.5, F.speed, payload: [1]),
            F.sample(2, seconds: 10, F.speed, payload: [1])
        ]
        await sessions.seed(session, pids: pids, samples: samples)

        let dataset = try await useCase.build(sessionID: session.id)

        XCTAssertEqual(dataset.gaps, [AnalysisGap(startSeconds: 1.5, endSeconds: 10), AnalysisGap(startSeconds: 10, endSeconds: 100)])
    }

    /// 責務: 整備記録を日付昇順のマーカーとして含めることを確認します。
    func testIncludesMaintenanceMarkersAscending() async throws {
        let vehicle = F.vehicle()
        let newer = MaintenanceRecord(vehicleID: vehicle.id, kind: .heavy, title: "Overhaul", performedAt: Date(timeIntervalSince1970: 2_000), odometerKilometers: 5000)
        let older = MaintenanceRecord(vehicleID: vehicle.id, kind: .light, title: "Oil", performedAt: Date(timeIntervalSince1970: 1_000))
        let (useCase, sessions) = makeSUT(vehicle: vehicle, records: [newer, older])
        let session = F.session(vehicleID: vehicle.id, sampleCount: 1)
        await sessions.seed(session, pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)], samples: [F.sample(0, seconds: 0, F.speed, payload: [1])])

        let dataset = try await useCase.build(sessionID: session.id)

        XCTAssertEqual(dataset.maintenance.map(\.title), ["Oil", "Overhaul"])
        XCTAssertEqual(dataset.maintenance[1].kind, "heavy")
        XCTAssertEqual(dataset.maintenance[1].odometerKilometers, 5000)
        XCTAssertEqual(dataset.session.distanceKilometers, 10)
        XCTAssertEqual(dataset.vehicle.name, "Test Car")
    }

    /// 責務: Rawが端末に無いセッションは失敗として報告することを確認します。
    func testCloudOnlySessionFailsAsRawUnavailable() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, raw: .cloudOnly, sampleCount: 5)
        await sessions.seed(session, pids: [], samples: [])
        do {
            _ = try await useCase.build(sessionID: session.id)
            XCTFail("失敗するはず")
        } catch {
            XCTAssertEqual(error as? AnalysisFailure, .rawUnavailable)
        }
    }

    /// 責務: 取得条件に無い要求を含むRawは不整合として失敗することを確認します。
    func testUnknownRequestFailsAsInconsistentRaw() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, sampleCount: 1)
        await sessions.seed(session, pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)], samples: [F.sample(0, seconds: 0, F.rpm, payload: [1, 2])])
        do {
            _ = try await useCase.build(sessionID: session.id)
            XCTFail("失敗するはず")
        } catch {
            XCTAssertEqual(error as? AnalysisFailure, .inconsistentRaw)
        }
    }

    /// 責務: 存在しないセッションと、サンプルが無いセッションを区別して失敗させることを確認します。
    func testMissingSessionAndEmptySession() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        do {
            _ = try await useCase.build(sessionID: SessionID())
            XCTFail("失敗するはず")
        } catch {
            XCTAssertEqual(error as? AnalysisFailure, .sessionNotFound)
        }
        let empty = F.session(vehicleID: vehicle.id, sampleCount: 0)
        await sessions.seed(empty, pids: F.standardPIDs(), samples: [])
        do {
            _ = try await useCase.build(sessionID: empty.id)
            XCTFail("失敗するはず")
        } catch {
            XCTAssertEqual(error as? AnalysisFailure, .noSamples)
        }
    }

    /// 責務: 符号化したJSONが列指向で、日付がISO 8601であることを確認します。
    func testEncodesColumnarJSON() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, sampleCount: 2)
        await sessions.seed(session, pids: [F.pid(F.speed, ordinal: 0, bytes: 1, formula: "A", unit: "km/h", min: 0, max: 255)], samples: [F.sample(0, seconds: 0, F.speed, payload: [5]), F.sample(1, seconds: 1, F.speed, payload: [6])])
        let dataset = try await useCase.build(sessionID: session.id)

        let json = try await AnalysisJSONEncoder.encode(dataset)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AnalysisDataset.currentSchemaVersion)
        let channels = try XCTUnwrap(object["channels"] as? [[String: Any]])
        XCTAssertEqual(channels[0]["values"] as? [Double], [5, 6])
        let info = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(info["startedAt"] as? String, "1970-01-12T13:46:40Z")
    }
}
