import XCTest
@testable import ProjectZD8

final class AcquisitionEngineTests: XCTestCase {
    private final class EngineBox: @unchecked Sendable { var engine: AcquisitionEngine? }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [OBDPIDRequest: Int] = [:]
        func next(_ request: OBDPIDRequest) -> Int {
            lock.withLock {
                counts[request, default: 0] += 1
                return counts[request]!
            }
        }
    }

    private typealias F = DriveFlowFixtures

    private let standardPIDs: [SessionPID] = [
        F.pid(0, F.rpm, fast: true), F.pid(1, F.speed, fast: true),
        F.pid(2, F.coolant), F.pid(3, F.odometer, formula: "A", bytes: 1, minimum: 0, maximum: 1000)
    ]

    private struct Harness {
        let engine: AcquisitionEngine
        let link: DriveFlowScriptedLink
        let repository: DriveFlowSessionRepository
        let clock: DriveFlowManualClock
        let session: DriveSession
    }

    /// 指定した通算要求番号の直後(ティック末)に停止を要求する取得エンジン一式を作ります。
    private func makeHarness(
        pids: [SessionPID]? = nil,
        queryDuration: Int64 = 0,
        stopAfterQuery: Int? = nil,
        noResponseTickLimit: Int = AcquisitionEngine.noResponseTickLimit,
        repository: DriveFlowSessionRepository = DriveFlowSessionRepository(),
        script: @escaping DriveFlowScriptedLink.Script = { _, _, _ in OBDQueryResult(outcome: .responded, payload: [50]) }
    ) -> Harness {
        let box = EngineBox()
        let clock = DriveFlowManualClock()
        let link = DriveFlowScriptedLink(
            clock: clock, queryDuration: queryDuration,
            onQuery: { index in if index == stopAfterQuery { box.engine?.requestStop() } },
            script: script
        )
        let session = F.session()
        repository.seed(session)
        let engine = AcquisitionEngine(
            link: link, session: session, pids: pids ?? standardPIDs, vehicleModelCode: nil, repository: repository,
            clock: clock, now: { F.epoch }, noResponseTickLimit: noResponseTickLimit
        )
        box.engine = engine
        return Harness(engine: engine, link: link, repository: repository, clock: clock, session: session)
    }

    private func run(_ harness: Harness) async throws -> (DriveSession, [AcquisitionEvent]) {
        let collector = Task { () -> [AcquisitionEvent] in
            var all: [AcquisitionEvent] = []
            for await event in harness.engine.events { all.append(event) }
            return all
        }
        let session = try await harness.engine.run()
        return (session, await collector.value)
    }

    func testSequenceIsContiguousAndEachTickIsOneAppend() async throws {
        let harness = makeHarness(queryDuration: 10_000, stopAfterQuery: 11)
        let (session, _) = try await run(harness)

        let batches = harness.repository.appended
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches.map(\.count), [4, 4, 4])
        let samples = batches.flatMap { $0 }
        XCTAssertEqual(samples.map(\.sequence), Array(0..<12))
        XCTAssertEqual(samples.map(\.tick), [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(session.endReason, .userStopped)
    }

    func testTickPeriodIsPaddedToMinimumAndElapsedUsesInjectedClock() async throws {
        let harness = makeHarness(queryDuration: 10_000, stopAfterQuery: 11)
        _ = try await run(harness)

        // 4 queries x 10 ms = 40 ms per tick, so 60 ms of padding.
        XCTAssertEqual(harness.clock.sleeps, [60_000, 60_000, 60_000])
        let samples = harness.repository.allSamples
        XCTAssertEqual(samples[0].elapsedMicroseconds, 10_000)
        XCTAssertEqual(samples[3].elapsedMicroseconds, 40_000)
        XCTAssertEqual(samples[4].elapsedMicroseconds, 110_000)
        XCTAssertEqual(samples.map(\.elapsedMicroseconds), samples.map(\.elapsedMicroseconds).sorted())
    }

    func testNoExtraSleepWhenQueriesAlreadyExceedPeriod() async throws {
        let harness = makeHarness(queryDuration: 50_000, stopAfterQuery: 7)
        _ = try await run(harness)
        XCTAssertEqual(harness.clock.sleeps, [])
    }

    func testNonResponsesAreRecordedWithEmptyPayloadAndPublishedAsNoResponse() async throws {
        let harness = makeHarness(stopAfterQuery: 3) { request, _, _ in
            request == F.coolant ? OBDQueryResult(outcome: .noData) : OBDQueryResult(outcome: .responded, payload: [7])
        }
        let (_, events) = try await run(harness)

        let samples = harness.repository.allSamples
        XCTAssertEqual(samples.count, 4)
        let coolant = try XCTUnwrap(samples.first { $0.request == F.coolant })
        XCTAssertEqual(coolant.outcome, .noData)
        XCTAssertTrue(coolant.payload.isEmpty)
        let tick = try XCTUnwrap(events.compactMap { event -> AcquisitionEvent.Tick? in
            if case .tick(let tick) = event { return tick } else { return nil }
        }.first)
        XCTAssertEqual(tick.readings.first { $0.request == F.coolant }?.reading, .noResponse(.noData))
        XCTAssertEqual(tick.sampleCount, 4)
        XCTAssertEqual(tick.respondedCount, 3)
        XCTAssertEqual(tick.responseRate, 0.75, accuracy: 1e-9)
    }

    func testQueriesAreInPollingOrderAndPassTheHeader() async throws {
        let pids = [F.pid(0, F.rpm, fast: true), F.pid(1, F.zd8Odometer, header: 0x7E0)]
        let harness = makeHarness(pids: pids, stopAfterQuery: 1)
        _ = try await run(harness)
        XCTAssertEqual(harness.link.queries, [
            DriveFlowScriptedLink.Query(request: F.rpm, header: nil),
            DriveFlowScriptedLink.Query(request: F.zd8Odometer, header: 0x7E0)
        ])
    }

    func testInvalidDecodesArePublishedAsInvalidNeverZero() async throws {
        let pids = [
            F.pid(0, F.rpm, fast: true, maximum: 100),
            F.pid(1, F.speed, fast: true),
            F.pid(2, F.coolant, formula: "A / 0", bytes: 1)
        ]
        let harness = makeHarness(pids: pids, stopAfterQuery: 2) { request, _, _ in
            switch request {
            case F.rpm: OBDQueryResult(outcome: .responded, payload: [200])
            case F.speed: OBDQueryResult(outcome: .responded, payload: [])
            default: OBDQueryResult(outcome: .responded, payload: [9])
            }
        }
        let (_, events) = try await run(harness)
        let tick = try XCTUnwrap(events.compactMap { event -> AcquisitionEvent.Tick? in
            if case .tick(let tick) = event { return tick } else { return nil }
        }.first)
        XCTAssertEqual(tick.readings.first { $0.request == F.rpm }?.reading, .outOfRange(200))
        XCTAssertEqual(tick.readings.first { $0.request == F.speed }?.reading, .decodeFailed)
        XCTAssertEqual(tick.readings.first { $0.request == F.coolant }?.reading, .decodeFailed)
        // The invalid samples are still stored as responded Raw.
        let samples = harness.repository.allSamples
        XCTAssertEqual(samples.filter { $0.outcome == .responded }.count, 3)
    }

    func testValidDecodeUsesSessionFormula() async throws {
        let pids = [F.pid(0, F.rpm, fast: true, formula: "(A * 256 + B) / 4", bytes: 2, maximum: 16_383.75)]
        let harness = makeHarness(pids: pids, stopAfterQuery: 0) { _, _, _ in OBDQueryResult(outcome: .responded, payload: [0x1A, 0xF8]) }
        let (_, events) = try await run(harness)
        let tick = try XCTUnwrap(events.compactMap { event -> AcquisitionEvent.Tick? in
            if case .tick(let tick) = event { return tick } else { return nil }
        }.first)
        XCTAssertEqual(tick.readings.first?.reading, .value(1726))
    }

    func testEventsStartWithStartedAndEndWithFinalSession() async throws {
        let harness = makeHarness(stopAfterQuery: 3)
        let (session, events) = try await run(harness)
        guard case .started(let start) = try XCTUnwrap(events.first) else { return XCTFail("first event is not started") }
        XCTAssertEqual(start.session.id, harness.session.id)
        XCTAssertEqual(start.pids, standardPIDs)
        guard case .ended(let ended) = try XCTUnwrap(events.last) else { return XCTFail("last event is not ended") }
        XCTAssertEqual(ended, session)
        XCTAssertEqual(ended.endReason, .userStopped)
    }

    // MARK: End conditions

    func testConnectionLostEndsSessionAndKeepsPartialTick() async throws {
        let harness = makeHarness { _, _, index in
            if index == 5 { throw OBDLinkError.connectionLost }
            return OBDQueryResult(outcome: .responded, payload: [1])
        }
        let (session, _) = try await run(harness)
        XCTAssertEqual(session.endReason, .connectionLost)
        let batches = harness.repository.appended
        XCTAssertEqual(batches.map(\.count), [4, 1])
        XCTAssertEqual(harness.link.closeCount, 1)
        let finishes = harness.repository.finishes
        XCTAssertEqual(finishes.count, 1)
    }

    func testVehicleNoResponseAfterTwentyConsecutiveSilentFastTicks() async throws {
        // Slow PIDs keep answering; only the fast group matters for the decision.
        let harness = makeHarness { request, _, _ in
            [F.rpm, F.speed].contains(request) ? OBDQueryResult(outcome: .timedOut) : OBDQueryResult(outcome: .responded, payload: [1])
        }
        let (session, _) = try await run(harness)
        XCTAssertEqual(session.endReason, .vehicleNoResponse)
        let batchCount = harness.repository.appended.count
        XCTAssertEqual(batchCount, 20)
        XCTAssertEqual(harness.link.closeCount, 1)
    }

    func testAResponseResetsTheSilentTickCounter() async throws {
        // Silent for 19 ticks, one good tick, then silent again: never reaches 20 in a row before the stop.
        let ticksPerQuery = 4
        let harness = makeHarness(stopAfterQuery: 40 * ticksPerQuery - 1) { request, _, index in
            let tick = index / ticksPerQuery
            let silent = tick != 19
            return [F.rpm, F.speed].contains(request) && silent
                ? OBDQueryResult(outcome: .noData) : OBDQueryResult(outcome: .responded, payload: [1])
        }
        let (session, _) = try await run(harness)
        // Ticks 0..18 silent (19), tick 19 responds, ticks 20..38 silent (19), tick 39 silent = 20 in a row.
        XCTAssertEqual(session.endReason, .vehicleNoResponse)
        let batchCount = harness.repository.appended.count
        XCTAssertEqual(batchCount, 40)
    }

    func testAppendFailureEndsWithAcquisitionFailedAndStillFinishesAndCloses() async throws {
        let repository = DriveFlowSessionRepository()
        repository.configure(failAppendAtCall: 1)
        let harness = makeHarness(repository: repository)
        let (session, _) = try await run(harness)
        XCTAssertEqual(session.endReason, .acquisitionFailed)
        XCTAssertEqual(harness.link.closeCount, 1)
        let finishes = repository.finishes
        XCTAssertEqual(finishes.count, 1)
    }

    func testRecordDistanceFailureEndsWithAcquisitionFailed() async throws {
        let repository = DriveFlowSessionRepository()
        repository.configure(failRecordDistance: true)
        let pids = [F.pid(0, F.rpm, fast: true), F.pid(1, F.odometer, minimum: 0, maximum: 1000)]
        let harness = makeHarness(pids: pids, repository: repository)
        let (session, _) = try await run(harness)
        XCTAssertEqual(session.endReason, .acquisitionFailed)
    }

    func testFinishFailureThrowsButStillClosesLinkOnce() async throws {
        let repository = DriveFlowSessionRepository()
        repository.configure(failFinish: true)
        let harness = makeHarness(stopAfterQuery: 3, repository: repository)
        do {
            _ = try await harness.engine.run()
            XCTFail("expected finishFailed")
        } catch {
            XCTAssertEqual(error as? AcquisitionEngineError, .finishFailed(.userStopped))
        }
        XCTAssertEqual(harness.link.closeCount, 1)
        let finishes = repository.finishes
        XCTAssertEqual(finishes.count, 1)
    }

    func testStopBeforeRunStillFinishesWithoutQueries() async throws {
        let harness = makeHarness()
        harness.engine.requestStop()
        let (session, _) = try await run(harness)
        XCTAssertEqual(session.endReason, .userStopped)
        XCTAssertTrue(harness.link.queries.isEmpty)
        XCTAssertEqual(harness.link.closeCount, 1)
    }

    func testRunTwiceThrowsAlreadyRun() async throws {
        let harness = makeHarness(stopAfterQuery: 3)
        _ = try await run(harness)
        do {
            _ = try await harness.engine.run()
            XCTFail("expected alreadyRun")
        } catch {
            XCTAssertEqual(error as? AcquisitionEngineError, .alreadyRun)
        }
        XCTAssertEqual(harness.link.closeCount, 1)
        let finishes = harness.repository.finishes
        XCTAssertEqual(finishes.count, 1)
    }

    // MARK: Distance

    func testDistanceFollowsSourcePriorityAndIsPersisted() async throws {
        let counter = Counter()
        let pids = [
            F.pid(0, F.rpm, fast: true),
            F.pid(1, F.sinceCleared, minimum: 0, maximum: 1000),
            F.pid(2, F.odometer, minimum: 0, maximum: 1000),
            F.pid(3, F.zd8Odometer, header: 0x7E0, minimum: 0, maximum: 1000)
        ]
        // 7 queries per tick would be too many; slow rotation is 2 per tick, so 3 slow PIDs need several ticks.
        let harness = makeHarness(pids: pids, stopAfterQuery: 29) { request, _, _ in
            switch request {
            case F.sinceCleared: OBDQueryResult(outcome: .responded, payload: [UInt8(counter.next(request))])
            case F.odometer: OBDQueryResult(outcome: .responded, payload: [UInt8(100 + counter.next(request))])
            case F.zd8Odometer: OBDQueryResult(outcome: .responded, payload: [UInt8(200 + counter.next(request))])
            default: OBDQueryResult(outcome: .responded, payload: [1])
            }
        }
        let (_, events) = try await run(harness)

        let records = harness.repository.distances
        XCTAssertFalse(records.isEmpty)
        let firstSpecific = try XCTUnwrap(records.firstIndex { $0.source == .vehicleSpecificOdometer })
        XCTAssertTrue(records[firstSpecific...].allSatisfy { $0.source == .vehicleSpecificOdometer })
        XCTAssertTrue(records[..<firstSpecific].allSatisfy { $0.source != .vehicleSpecificOdometer })
        let last = try XCTUnwrap(records.last)
        XCTAssertGreaterThan(last.end, last.start)
        XCTAssertGreaterThanOrEqual(last.start, 201)
        XCTAssertTrue(harness.link.queries.contains(DriveFlowScriptedLink.Query(request: F.zd8Odometer, header: 0x7E0)))
        let lastTick = try XCTUnwrap(events.compactMap { event -> AcquisitionEvent.Tick? in
            if case .tick(let tick) = event { return tick } else { return nil }
        }.last)
        XCTAssertEqual(try XCTUnwrap(lastTick.distanceKilometers), last.end - last.start, accuracy: 1e-9)
    }

    func testInvalidOdometerValuesAreNotRecordedAsDistance() async throws {
        let pids = [F.pid(0, F.rpm, fast: true), F.pid(1, F.odometer, minimum: 0, maximum: 100)]
        let harness = makeHarness(pids: pids, stopAfterQuery: 5) { request, _, _ in
            OBDQueryResult(outcome: .responded, payload: [request == F.odometer ? 250 : 1])
        }
        _ = try await run(harness)
        let records = harness.repository.distances
        XCTAssertTrue(records.isEmpty)
    }
}
