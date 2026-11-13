import XCTest
@testable import ProjectZD8

/// デモリンクの決定性、物理的な整合、カタログの数式での復号を検証します。
final class DemoOBDLinkTests: XCTestCase {
    private let evaluator = OBDPIDFormulaEvaluator()
    private let odometer = OBDPIDRequest(service: 0x21, pid: 0x02)
    private let fluidTemperature = OBDPIDRequest(service: 0x21, pid: 0x17)

    private func makeLink(clock: DevicesManualClock) -> DemoOBDLink {
        DemoOBDLink(latency: .zero, now: { Date(timeIntervalSince1970: 0) }, elapsedSeconds: { clock.read() })
    }

    private func decoded(_ link: DemoOBDLink, _ request: OBDPIDRequest, header: UInt16? = nil) async throws -> Double {
        let result = try await link.query(request, header: header)
        XCTAssertEqual(result.outcome, .responded, "pid \(request.pid)")
        let definition = try XCTUnwrap(OBDPIDCatalog.definition(for: request, vehicleModelCode: ZD8VehicleModelPolicy.modelCode))
        return try evaluator.evaluate(definition, bytes: result.payload)
    }

    /// 責務: 対応する全PIDの値が、10分間のどの時刻でもカタログの範囲内に復号できることを確認します。
    func testAllSupportedPIDsDecodeWithinCatalogRanges() async throws {
        let clock = DevicesManualClock()
        let link = makeLink(clock: clock)
        let supported = try await link.supportedPIDs()
        XCTAssertFalse(supported.isEmpty)

        for second in stride(from: 0.0, through: 600.0, by: 2.5) {
            clock.set(second)
            for request in supported {
                let definition = try XCTUnwrap(OBDPIDCatalog.definition(for: request, vehicleModelCode: nil))
                let value = try await decoded(link, request)
                XCTAssertGreaterThanOrEqual(value, definition.minimumValue ?? -.infinity, "pid \(request.pid) t=\(second)")
                XCTAssertLessThanOrEqual(value, definition.maximumValue ?? .infinity, "pid \(request.pid) t=\(second)")
            }
        }
    }

    /// 責務: 同じ時刻に対して常に同じバイト列を返す(決定的)ことを確認します。
    func testSameTimeYieldsSameBytes() async throws {
        let first = makeLink(clock: DevicesManualClock(137))
        let second = makeLink(clock: DevicesManualClock(137))
        for pid: UInt8 in [0x0C, 0x0D, 0x05, 0x10] {
            let request = OBDPIDRequest(service: 0x01, pid: pid)
            let a = try await first.query(request, header: nil)
            let b = try await second.query(request, header: nil)
            XCTAssertEqual(a, b)
        }
    }

    /// 責務: 停止中はアイドル回転、巡航中は車速に見合った回転数になることを確認します。
    func testRPMFollowsSpeed() async throws {
        let clock = DevicesManualClock(5)
        let link = makeLink(clock: clock)
        let idleSpeed = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x0D))
        let idleRPM = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x0C))
        XCTAssertEqual(idleSpeed, 0)
        XCTAssertTrue((700...1_300).contains(idleRPM), "idle rpm \(idleRPM)")

        clock.set(60 + DemoDriveCycle.cycleDuration * 3)
        let cruiseSpeed = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x0D))
        let cruiseRPM = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x0C))
        XCTAssertEqual(cruiseSpeed, 80)
        XCTAssertTrue((1_500...2_600).contains(cruiseRPM), "cruise rpm \(cruiseRPM)")
    }

    /// 責務: 加速中は巡航中よりスロットル・負荷・吸入空気量が大きいことを確認します。
    func testAccelerationHasHigherLoadThanCruise() async throws {
        let clock = DevicesManualClock(DemoDriveCycle.cycleDuration * 3 + 30)
        let link = makeLink(clock: clock)
        var accelerating: [Double] = []
        for pid: UInt8 in [0x11, 0x04, 0x10] {
            accelerating.append(try await decoded(link, OBDPIDRequest(service: 0x01, pid: pid)))
        }
        clock.set(DemoDriveCycle.cycleDuration * 3 + 60)
        var cruising: [Double] = []
        for pid: UInt8 in [0x11, 0x04, 0x10] {
            cruising.append(try await decoded(link, OBDPIDRequest(service: 0x01, pid: pid)))
        }
        for (a, c) in zip(accelerating, cruising) { XCTAssertGreaterThan(a, c) }
    }

    /// 責務: 冷間始動から冷却水温と油温・AT油温が単調に上昇し、暖機後は約88度に近づくことを確認します。
    func testWarmUpIsMonotonic() async throws {
        let clock = DevicesManualClock()
        let link = makeLink(clock: clock)
        var previous = (coolant: -100.0, oil: -100.0, fluid: -100.0)
        for second in stride(from: 0.0, through: 1_800.0, by: 30) {
            clock.set(second)
            let coolant = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x05))
            let oil = try await decoded(link, OBDPIDRequest(service: 0x01, pid: 0x5C))
            let fluid = try await decoded(link, fluidTemperature, header: 0x7E1)
            XCTAssertGreaterThanOrEqual(coolant, previous.coolant)
            XCTAssertGreaterThanOrEqual(oil, previous.oil)
            XCTAssertGreaterThanOrEqual(fluid, previous.fluid)
            previous = (coolant, oil, fluid)
        }
        XCTAssertEqual(previous.coolant, 88, accuracy: 3)
    }

    /// 責務: ZD8の走行距離計が単調に増え、車両が動いた分だけ進むことを確認します。
    func testOdometerIsMonotonicAndAdvances() async throws {
        let clock = DevicesManualClock()
        let link = makeLink(clock: clock)
        var previous = try await decoded(link, odometer, header: 0x7E0)
        XCTAssertEqual(previous, 48_213.4, accuracy: 0.05)
        for second in stride(from: 1.0, through: 600.0, by: 1.0) {
            clock.set(second)
            let value = try await decoded(link, odometer, header: 0x7E0)
            XCTAssertGreaterThanOrEqual(value, previous, "t=\(second)")
            previous = value
        }
        XCTAssertGreaterThan(previous - 48_213.4, 5)
    }

    /// 責務: VINがJF1ZD8で始まりZD8専用PIDの適用対象になることと、アダプターがデモ経路であることを確認します。
    func testIdentificationMatchesZD8() async throws {
        let link = makeLink(clock: DevicesManualClock())
        let identification = try await link.identify()
        let vin = try XCTUnwrap(identification.vin)
        XCTAssertTrue(vin.hasPrefix("JF1ZD8"))
        XCTAssertEqual(vin.count, 17)
        XCTAssertTrue(ZD8VehicleModelPolicy().matches(vin))
        XCTAssertEqual(DemoOBDLink.adapter.transport, .demo)
    }

    /// 責務: 未対応PIDや、専用PIDへの誤ったヘッダーは `.noData` になることを確認します。
    func testUnsupportedRequestsReturnNoData() async throws {
        let link = makeLink(clock: DevicesManualClock())
        let unsupported = try await link.query(OBDPIDRequest(service: 0x01, pid: 0xA6), header: nil)
        let wrongHeader = try await link.query(odometer, header: 0x7E1)
        let missingHeader = try await link.query(odometer, header: nil)
        XCTAssertEqual([unsupported, wrongHeader, missingHeader], Array(repeating: OBDQueryResult(outcome: .noData), count: 3))
    }

    /// 責務: closeの後は `connectionLost` になることを確認します。
    func testClosedLinkThrowsConnectionLost() async throws {
        let link = makeLink(clock: DevicesManualClock())
        await link.close()
        do {
            _ = try await link.query(OBDPIDRequest(service: 0x01, pid: 0x0C), header: nil)
            XCTFail("閉じたリンクが応答した")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .connectionLost)
        }
    }
}
