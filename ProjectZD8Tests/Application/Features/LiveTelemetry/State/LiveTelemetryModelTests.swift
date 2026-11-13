import XCTest
@testable import ProjectZD8

@MainActor
final class LiveTelemetryModelTests: XCTestCase {
    private typealias F = DriveFlowFixtures

    private func spec(_ ordinal: Int, _ request: OBDPIDRequest, unit: String = "u", maximum: Double? = 255) -> LiveTelemetryEvent.ChannelSpec {
        .init(request: request, ordinal: ordinal, nameKey: "name.\(ordinal)", unit: unit, minimumValue: 0, maximumValue: maximum)
    }

    private func started(_ specs: [LiveTelemetryEvent.ChannelSpec]) -> LiveTelemetryEvent {
        .sessionStarted(.init(sessionID: SessionID(), adapterName: "A", channels: specs))
    }

    private func tick(_ micro: Int64, _ readings: [(OBDPIDRequest, LiveTelemetryEvent.Reading)], samples: Int = 1) -> LiveTelemetryEvent {
        .tick(.init(
            elapsedMicroseconds: micro, readings: readings.map { .init(request: $0.0, reading: $0.1) },
            sampleCount: samples, respondedCount: samples, distanceKilometers: nil
        ))
    }

    private func makeModel() -> LiveTelemetryModel { LiveTelemetryModel(feed: LiveTelemetryFeedBroadcaster()) }

    func testChannelsAreCreatedFromSessionStartWithCategoryAndPrimaries() {
        let model = makeModel()
        model.apply(started([
            spec(2, F.coolant, unit: "°C"), spec(0, F.rpm, unit: "rpm"), spec(1, F.speed, unit: "km/h"),
            spec(3, F.zd8Odometer, unit: "km"), spec(4, OBDPIDRequest(service: 0x21, pid: 0x17), unit: "°C")
        ]))
        XCTAssertEqual(model.state.status, .live)
        XCTAssertEqual(model.state.channels.map(\.ordinal), [0, 1, 2, 3, 4])
        XCTAssertEqual(model.state.rpm?.request, F.rpm)
        XCTAssertEqual(model.state.speed?.request, F.speed)
        XCTAssertEqual(model.state.rpm?.category, .engine)
        XCTAssertEqual(model.state.speed?.category, .driving)
        XCTAssertEqual(model.state.channel(for: F.coolant)?.category, .temperature)
        XCTAssertEqual(model.state.channel(for: F.zd8Odometer)?.category, .diagnostics)
        XCTAssertEqual(model.state.channels[4].category, .temperature)
        XCTAssertEqual(model.state.channels(in: .temperature).map(\.ordinal), [2, 4])
        XCTAssertEqual(model.state.rpm?.validity, .awaiting)
        XCTAssertNil(model.state.rpm?.value)
    }

    func testValuesAndHeaderStatsAreApplied() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        model.apply(.tick(.init(
            elapsedMicroseconds: 500_000, readings: [.init(request: F.rpm, reading: .value(1500))],
            sampleCount: 4, respondedCount: 3, distanceKilometers: 1.5
        )))
        XCTAssertEqual(model.state.rpm?.value, 1500)
        XCTAssertEqual(model.state.rpm?.validity, .valid)
        XCTAssertEqual(model.state.elapsedMicroseconds, 500_000)
        XCTAssertEqual(model.state.sampleCount, 4)
        XCTAssertEqual(model.state.responseRate, 0.75, accuracy: 1e-9)
        XCTAssertEqual(model.state.distanceKilometers, 1.5)
    }

    func testInvalidReadingsClearTheValueAndAreNotAddedToHistory() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        model.apply(tick(1_000_000, [(F.rpm, .value(900))]))
        model.apply(tick(2_000_000, [(F.rpm, .outOfRange(99_999))]))
        XCTAssertNil(model.state.rpm?.value)
        XCTAssertEqual(model.state.rpm?.validity, .outOfRange(99_999))
        model.apply(tick(3_000_000, [(F.rpm, .decodeFailed)]))
        XCTAssertEqual(model.state.rpm?.validity, .decodeFailed)
        model.apply(tick(4_000_000, [(F.rpm, .noResponse(.timedOut))]))
        XCTAssertEqual(model.state.rpm?.validity, .noResponse(.timedOut))
        XCTAssertNil(model.state.rpm?.value)
        XCTAssertEqual(model.state.rpm?.history.map(\.value), [900])
    }

    func testHistoryIsBoundedToTheLastHundredTwentySeconds() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        for second in 0...300 {
            model.apply(tick(Int64(second) * 1_000_000, [(F.rpm, .value(Double(second)))]))
        }
        let history = try? XCTUnwrap(model.state.rpm?.history)
        XCTAssertEqual(history?.count, 121)
        XCTAssertEqual(history?.first?.elapsedMicroseconds, 180_000_000)
        XCTAssertEqual(history?.last?.elapsedMicroseconds, 300_000_000)
    }

    func testEndKeepsLastValuesAsStaleAndIgnoresLateTicks() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        model.apply(tick(1_000_000, [(F.rpm, .value(2000))]))
        model.apply(.sessionEnded(.connectionLost))
        XCTAssertEqual(model.state.status, .stale(.connectionLost))
        XCTAssertTrue(model.state.isStale)
        XCTAssertEqual(model.state.rpm?.value, 2000)
        model.apply(tick(2_000_000, [(F.rpm, .value(5000))]))
        XCTAssertEqual(model.state.rpm?.value, 2000)
    }

    func testNewSessionResetsEverything() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        model.apply(tick(1_000_000, [(F.rpm, .value(2000))], samples: 9))
        model.apply(.sessionEnded(.userStopped))
        model.apply(started([spec(0, F.speed)]))
        XCTAssertEqual(model.state.status, .live)
        XCTAssertNil(model.state.rpm)
        XCTAssertEqual(model.state.sampleCount, 0)
        XCTAssertEqual(model.state.channels.map(\.request), [F.speed])
        XCTAssertEqual(model.state.speed?.history, [])
    }

    func testClearOnlyWhenNotLive() {
        let model = makeModel()
        model.apply(started([spec(0, F.rpm)]))
        model.send(.clearRequested)
        XCTAssertEqual(model.state.status, .live)
        model.apply(.sessionEnded(.userStopped))
        model.send(.clearRequested)
        XCTAssertEqual(model.state, LiveTelemetryState())
    }

    func testBroadcasterFeedsTheModelFromEngineEvents() async throws {
        let broadcaster = LiveTelemetryFeedBroadcaster()
        let model = LiveTelemetryModel(feed: broadcaster)
        let pids = [F.pid(0, F.rpm, fast: true), F.pid(1, F.speed, fast: true), F.pid(2, F.coolant, enabled: false)]
        var session = F.session()
        broadcaster.publish(.started(.init(session: session, pids: pids, vehicleModelCode: nil)))
        broadcaster.publish(.tick(.init(
            tick: 0, elapsedMicroseconds: 100_000,
            readings: [.init(request: F.rpm, reading: .value(1000)), .init(request: F.speed, reading: .noResponse(.noData))],
            sampleCount: 2, respondedCount: 1, distanceKilometers: nil
        )))
        let arrived = await F.waitUntil { model.state.rpm?.value == 1000 }
        XCTAssertTrue(arrived)
        XCTAssertEqual(model.state.channels.map(\.request), [F.rpm, F.speed], "disabled PIDs get no channel")
        XCTAssertEqual(model.state.rpm?.nameKey, "obd.pid.01.0C.name")
        XCTAssertEqual(model.state.speed?.validity, .noResponse(.noData))
        session.endedAt = F.epoch
        session.endReason = .vehicleNoResponse
        broadcaster.publish(.ended(session))
        let ended = await F.waitUntil { model.state.status == .stale(.vehicleNoResponse) }
        XCTAssertTrue(ended)
    }
}
