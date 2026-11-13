import XCTest
@testable import ProjectZD8

/// 車両の長期傾向の集計を検証します。
final class BuildVehicleTrendDatasetUseCaseTests: XCTestCase {
    private typealias F = AnalysisFixtures

    /// 責務: アイドル10秒の後に巡航10秒を走るセッションのサンプルを作ります。
    private func drive() -> [SessionSample] {
        var samples: [SessionSample] = []
        var sequence: Int64 = 0
        for second in 0..<20 {
            let idle = second < 10
            let rpmValue: UInt16 = idle ? 3_200 : 8_000      // 800 / 2000 rpm
            let speedValue: UInt8 = idle ? 0 : 60
            let coolantValue: UInt8 = 130                   // 90 ℃
            samples.append(F.sample(sequence, seconds: Double(second), F.rpm, payload: [UInt8(rpmValue >> 8), UInt8(rpmValue & 0xFF)])); sequence += 1
            samples.append(F.sample(sequence, seconds: Double(second), F.speed, payload: [speedValue])); sequence += 1
            samples.append(F.sample(sequence, seconds: Double(second), F.coolant, payload: [coolantValue])); sequence += 1
        }
        return samples
    }

    /// 責務: 検証用のユースケースを作ります。
    private func makeSUT(vehicle: Vehicle, records: [MaintenanceRecord] = []) -> (BuildVehicleTrendDatasetUseCase, AnalysisFakeSessionRepository) {
        let sessions = AnalysisFakeSessionRepository()
        let useCase = BuildVehicleTrendDatasetUseCase(
            sessions: sessions,
            decoder: AnalysisSessionDecoder(sessions: sessions, pageSize: 7),
            vehicles: AnalysisFakeVehicleRepository([vehicle]),
            maintenance: AnalysisFakeMaintenanceRepository(records),
            names: AnalysisFakeNameResolver()
        )
        return (useCase, sessions)
    }

    /// 責務: 条件別の件数と分位数が仕様どおりに集計されることを確認します。
    func testAggregatesPerCondition() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let session = F.session(vehicleID: vehicle.id, duration: 20, sampleCount: 60)
        await sessions.seed(session, pids: F.standardPIDs(), samples: drive())

        let trend = try await useCase.build(vehicleID: vehicle.id)

        XCTAssertEqual(trend.sessions.count, 1)
        let stats = trend.sessions[0].stats
        func stat(_ channel: String, _ condition: VehicleTrendCondition) -> VehicleTrendStat? {
            stats.first { $0.channelId == channel && $0.condition == condition }
        }
        let all = try XCTUnwrap(stat("01-0C", .all))
        XCTAssertEqual(all.count, 20)
        XCTAssertEqual(all.median, 1_400, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stat("01-0C", .warmIdle)).count, 10)
        XCTAssertEqual(try XCTUnwrap(stat("01-0C", .warmIdle)).median, 800, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stat("01-05", .warmIdle)).count, 10)
        XCTAssertEqual(try XCTUnwrap(stat("01-0C", .steadyCruise)).count, 7)
        XCTAssertEqual(try XCTUnwrap(stat("01-0C", .steadyCruise)).median, 2_000, accuracy: 0.001)
        XCTAssertEqual(trend.channels.map(\.id), ["01-0C", "01-0D", "01-05"])
    }

    /// 責務: デモは既定で除外し、iCloudにだけあるセッションは件数として報告することを確認します。
    func testExcludesDemoAndReportsCloudOnly() async throws {
        let vehicle = F.vehicle()
        let (useCase, sessions) = makeSUT(vehicle: vehicle)
        let real = F.session(vehicleID: vehicle.id, startedAt: Date(timeIntervalSince1970: 2_000_000), duration: 20, sampleCount: 60)
        let demo = F.session(vehicleID: vehicle.id, startedAt: Date(timeIntervalSince1970: 1_000_000), duration: 20, isDemo: true, sampleCount: 60)
        let cloud = F.session(vehicleID: vehicle.id, startedAt: Date(timeIntervalSince1970: 3_000_000), duration: 20, raw: .cloudOnly, sampleCount: 60)
        await sessions.seed(real, pids: F.standardPIDs(), samples: drive())
        await sessions.seed(demo, pids: F.standardPIDs(), samples: drive())
        await sessions.seed(cloud, pids: [], samples: [])

        let excluded = try await useCase.build(vehicleID: vehicle.id)
        XCTAssertEqual(excluded.sessions.map(\.id), [real.id.rawValue.uuidString])
        XCTAssertEqual(excluded.excludedDemoSessions, 1)
        XCTAssertEqual(excluded.skippedCloudOnlySessions, 1)

        let included = try await useCase.build(vehicleID: vehicle.id, includeDemo: true)
        XCTAssertEqual(included.sessions.map(\.id), [demo.id.rawValue.uuidString, real.id.rawValue.uuidString], "開始日時の昇順")
        XCTAssertTrue(included.sessions[0].isDemo)
    }

    /// 責務: 整備マーカーを含めることを確認します。
    func testIncludesMaintenance() async throws {
        let vehicle = F.vehicle()
        let record = MaintenanceRecord(vehicleID: vehicle.id, kind: .light, title: "Oil", performedAt: Date(timeIntervalSince1970: 5))
        let (useCase, _) = makeSUT(vehicle: vehicle, records: [record])
        let trend = try await useCase.build(vehicleID: vehicle.id)
        XCTAssertEqual(trend.maintenance.map(\.title), ["Oil"])
    }

    /// 責務: 未登録の車両は失敗として報告することを確認します。
    func testUnknownVehicleFails() async throws {
        let (useCase, _) = makeSUT(vehicle: F.vehicle())
        do {
            _ = try await useCase.build(vehicleID: VehicleID())
            XCTFail("失敗するはず")
        } catch {
            XCTAssertEqual(error as? AnalysisFailure, .vehicleNotFound)
        }
    }
}
