import XCTest
@testable import ProjectZD8

@MainActor
final class DriveSessionModelTests: XCTestCase {
    private typealias F = DriveFlowFixtures

    private final class EndedBox {
        var sessions: [DriveSession] = []
    }

    private struct Harness {
        let model: DriveSessionModel
        let link: DriveFlowScriptedLink
        let linkPort: DriveFlowLinkPort
        let vehicles: DriveFlowVehicleRepository
        let sessions: DriveFlowSessionRepository
        let inhibitor: DriveFlowSleepInhibitor
        let recorder: DriveFlowEventRecorder
        let ended: EndedBox
    }

    private func makeHarness(
        link: DriveFlowScriptedLink = DriveFlowScriptedLink(),
        linkError: OBDLinkError? = nil,
        vehicles: [Vehicle] = [],
        sessions: DriveFlowSessionRepository = DriveFlowSessionRepository(),
        vehicleRepository: DriveFlowVehicleRepository? = nil
    ) -> Harness {
        let linkPort = linkError.map { DriveFlowLinkPort(error: $0) } ?? DriveFlowLinkPort(link: link)
        let vehicleRepository = vehicleRepository ?? DriveFlowVehicleRepository(vehicles: vehicles)
        let inhibitor = DriveFlowSleepInhibitor()
        let recorder = DriveFlowEventRecorder()
        let ended = EndedBox()
        let model = DriveSessionModel(
            linkPort: linkPort,
            vehicles: vehicleRepository,
            sessions: sessions,
            preparePIDs: PrepareSessionPIDsUseCase(settings: DriveFlowPIDSettingRepository(), now: { F.epoch }),
            environment: DriveFlowEnvironment(),
            sleepInhibitor: inhibitor,
            events: recorder,
            clock: DriveFlowManualClock(),
            now: { F.epoch },
            onSessionEnded: { ended.sessions.append($0) }
        )
        return Harness(model: model, link: link, linkPort: linkPort, vehicles: vehicleRepository, sessions: sessions, inhibitor: inhibitor, recorder: recorder, ended: ended)
    }

    private func waitForPhase(_ harness: Harness, _ phase: DriveSessionPhase) async -> Bool {
        await F.waitUntil { harness.model.state.phase == phase }
    }

    private func waitForIdleAfterRun(_ harness: Harness) async -> Bool {
        await F.waitUntil { harness.model.state.phase == .idle && (harness.model.state.failure != nil || harness.model.state.lastEndedSession != nil) }
    }

    private func recordAndStop(_ harness: Harness) async {
        let recording = await waitForPhase(harness, .recording)
        XCTAssertTrue(recording)
        let ticked = await F.waitUntil { (harness.model.state.activeSession?.tickCount ?? 0) >= 3 }
        XCTAssertTrue(ticked)
        harness.model.send(.stopRequested)
        XCTAssertEqual(harness.model.state.phase, .stopping)
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)
    }

    // MARK: Happy paths

    func testKnownVehicleRecordsAndStops() async throws {
        let vehicle = F.vehicle()
        let harness = makeHarness(vehicles: [vehicle])
        harness.model.send(.connectRequested(F.adapter()))
        XCTAssertEqual(harness.model.state.phase, .connecting)
        XCTAssertEqual(harness.model.state.adapter, F.adapter())

        let recording = await waitForPhase(harness, .recording)
        XCTAssertTrue(recording)
        let ticked = await F.waitUntil { (harness.model.state.activeSession?.tickCount ?? 0) >= 3 }
        XCTAssertTrue(ticked)
        let summary = try XCTUnwrap(harness.model.state.activeSession)
        XCTAssertEqual(summary.vehicleName, "My ZD8")
        XCTAssertEqual(summary.adapterName, "OBDLink CX")
        XCTAssertFalse(summary.isDemo)
        XCTAssertGreaterThan(summary.sampleCount, 0)
        XCTAssertEqual(summary.responseRate, 1, accuracy: 1e-9)
        XCTAssertEqual(harness.inhibitor.calls, [true])

        harness.model.send(.stopRequested)
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)

        let state = harness.model.state
        XCTAssertNil(state.failure)
        XCTAssertNil(state.activeSession)
        XCTAssertNil(state.adapter)
        XCTAssertEqual(state.lastEndedSession?.endReason, .userStopped)
        XCTAssertEqual(harness.ended.sessions.count, 1)
        XCTAssertEqual(harness.inhibitor.calls, [true, false])
        XCTAssertEqual(harness.link.closeCount, 1)
        let begun = harness.sessions.begun
        XCTAssertEqual(begun.count, 1)
        let session = try XCTUnwrap(begun.first?.session)
        XCTAssertEqual(session.vehicleID, vehicle.id)
        XCTAssertEqual(session.deviceID, "device-1")
        XCTAssertEqual(session.appBuild, "7")
        XCTAssertEqual(session.platform, .mac)
        XCTAssertEqual(session.pollingPolicyVersion, AcquisitionPollingPolicy.version)
        XCTAssertFalse(session.isDemo)
        let finishes = harness.sessions.finishes
        XCTAssertEqual(finishes.count, 1)
        let savedVehicles = harness.vehicles.saved
        XCTAssertEqual(savedVehicles.count, 1, "a known vehicle is not re-registered")
    }

    func testEventsAreForwardedStartedTicksEnded() async throws {
        let harness = makeHarness(vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter()))
        await recordAndStop(harness)
        let events = harness.recorder.events
        guard case .started = try XCTUnwrap(events.first) else { return XCTFail("first is not started") }
        guard case .ended = try XCTUnwrap(events.last) else { return XCTFail("last is not ended") }
        XCTAssertTrue(events.contains { if case .tick = $0 { true } else { false } })
    }

    func testVehicleMatchIsCaseInsensitive() async {
        let harness = makeHarness(vehicles: [F.vehicle(vin: "wvwzzz1jzxw000001")])
        harness.model.send(.connectRequested(F.adapter()))
        await recordAndStop(harness)
        let count = harness.vehicles.saved.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(harness.model.state.activeSession?.vehicleName, nil)
        let begun = harness.sessions.begun
        XCTAssertEqual(begun.count, 1)
    }

    func testDemoAdapterRecordsADemoSession() async throws {
        let harness = makeHarness(vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter(transport: .demo)))
        await recordAndStop(harness)
        let begun = harness.sessions.begun
        XCTAssertTrue(try XCTUnwrap(begun.first).session.isDemo)
    }

    // MARK: Registration

    func testUnknownVINAsksForRegistrationThenCreatesTheVehicle() async throws {
        let harness = makeHarness()
        harness.model.send(.connectRequested(F.adapter()))
        let identification = F.identification()
        let waiting = await waitForPhase(harness, .awaitingVehicleRegistration(identification))
        XCTAssertTrue(waiting)

        harness.model.send(.registrationSubmitted(name: "   "))
        XCTAssertEqual(harness.model.state.phase, .awaitingVehicleRegistration(identification), "blank names are ignored")

        harness.model.send(.registrationSubmitted(name: "  Roadster  "))
        await recordAndStop(harness)

        let saved = harness.vehicles.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "Roadster")
        XCTAssertEqual(saved.first?.vin, "WVWZZZ1JZXW000001")
        let begun = harness.sessions.begun
        XCTAssertEqual(begun.first?.session.vehicleID, saved.first?.id)
        XCTAssertNil(harness.model.state.failure)
    }

    func testRegistrationCancelledClosesTheLinkWithoutFailure() async {
        let harness = makeHarness()
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForPhase(harness, .awaitingVehicleRegistration(F.identification()))
        harness.model.send(.registrationCancelled)
        let idle = await waitForPhase(harness, .idle)
        XCTAssertTrue(idle)
        XCTAssertNil(harness.model.state.failure)
        XCTAssertEqual(harness.link.closeCount, 1)
        let begun = harness.sessions.begun
        XCTAssertTrue(begun.isEmpty)
        let saved = harness.vehicles.saved
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(harness.ended.sessions.isEmpty)
    }

    func testStopWhileAwaitingRegistrationReturnsToIdle() async {
        let harness = makeHarness()
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForPhase(harness, .awaitingVehicleRegistration(F.identification()))
        harness.model.send(.stopRequested)
        let idle = await waitForPhase(harness, .idle)
        XCTAssertTrue(idle)
        XCTAssertNil(harness.model.state.failure)
        XCTAssertEqual(harness.link.closeCount, 1)
    }

    func testRegistrationSaveFailureReportsTheAwaitingPhase() async {
        let vehicles = DriveFlowVehicleRepository()
        vehicles.configure(failSave: true)
        let harness = makeHarness(vehicleRepository: vehicles)
        harness.model.send(.connectRequested(F.adapter()))
        let identification = F.identification()
        _ = await waitForPhase(harness, .awaitingVehicleRegistration(identification))
        harness.model.send(.registrationSubmitted(name: "X"))
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .awaitingVehicleRegistration(identification), kind: .store))
        XCTAssertEqual(harness.link.closeCount, 1)
    }

    // MARK: Failures

    func testConnectFailureCarriesTheConnectingPhase() async {
        let harness = makeHarness(linkError: .connectionFailed)
        harness.model.send(.connectRequested(F.adapter()))
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .connecting, kind: .link(.connectionFailed)))
        XCTAssertNil(harness.model.state.adapter)
        XCTAssertTrue(harness.inhibitor.calls.isEmpty)
    }

    func testMissingVINIsAFailureNotAGuess() async {
        let link = DriveFlowScriptedLink(identification: .success(F.identification(vin: nil)))
        let harness = makeHarness(link: link)
        harness.model.send(.connectRequested(F.adapter()))
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .identifying, kind: .vinMissing))
        XCTAssertEqual(link.closeCount, 1)
        let saved = harness.vehicles.saved
        XCTAssertTrue(saved.isEmpty)
    }

    func testBlankVINIsAlsoMissing() async {
        let link = DriveFlowScriptedLink(identification: .success(F.identification(vin: "  ")))
        let harness = makeHarness(link: link)
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.model.state.failure?.kind, .vinMissing)
    }

    func testVINUnavailableLinkErrorMapsToVinMissing() async {
        let link = DriveFlowScriptedLink(identification: .failure(.vinUnavailable))
        let harness = makeHarness(link: link)
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .identifying, kind: .vinMissing))
    }

    func testIdentifyLinkFailureClosesTheLink() async {
        let link = DriveFlowScriptedLink(identification: .failure(.timedOut))
        let harness = makeHarness(link: link)
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .identifying, kind: .link(.timedOut)))
        XCTAssertEqual(link.closeCount, 1)
    }

    func testNoPollablePIDsFailsInPreparing() async {
        let link = DriveFlowScriptedLink(supported: [])
        let harness = makeHarness(link: link, vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .preparing, kind: .noPollablePIDs))
        XCTAssertEqual(link.closeCount, 1)
        let begun = harness.sessions.begun
        XCTAssertTrue(begun.isEmpty)
    }

    func testSessionBeginFailureClosesLinkAndNeverInhibitsSleep() async {
        let sessions = DriveFlowSessionRepository()
        sessions.configure(failBegin: true)
        let harness = makeHarness(vehicles: [F.vehicle()], sessions: sessions)
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .preparing, kind: .store))
        XCTAssertEqual(harness.link.closeCount, 1)
        XCTAssertTrue(harness.inhibitor.calls.isEmpty)
    }

    func testConnectionLostDuringRecordingEndsAsInterruptedSession() async throws {
        let link = DriveFlowScriptedLink(script: { _, _, index in
            if index >= 12 { throw OBDLinkError.connectionLost }
            return OBDQueryResult(outcome: .responded, payload: [1])
        })
        let harness = makeHarness(link: link, vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter()))
        let done = await waitForIdleAfterRun(harness)
        XCTAssertTrue(done)
        let ended = try XCTUnwrap(harness.model.state.lastEndedSession)
        XCTAssertEqual(ended.endReason, .connectionLost)
        XCTAssertTrue(ended.wasInterrupted)
        XCTAssertNil(harness.model.state.failure)
        XCTAssertEqual(harness.ended.sessions.map(\.endReason), [.connectionLost])
        XCTAssertEqual(harness.inhibitor.calls, [true, false])
        XCTAssertEqual(link.closeCount, 1)
    }

    func testFinishFailureIsReportedAsRecordingStoreFailure() async {
        let sessions = DriveFlowSessionRepository()
        sessions.configure(failFinish: true)
        let harness = makeHarness(vehicles: [F.vehicle()], sessions: sessions)
        harness.model.send(.connectRequested(F.adapter()))
        await recordAndStop(harness)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .recording, kind: .store))
        XCTAssertNil(harness.model.state.lastEndedSession)
        XCTAssertEqual(harness.link.closeCount, 1)
        XCTAssertEqual(harness.inhibitor.calls, [true, false])
    }

    func testFailureCanBeDismissedAndIsClearedByNextConnect() async {
        let harness = makeHarness(linkError: .timedOut)
        harness.model.send(.connectRequested(F.adapter()))
        _ = await waitForIdleAfterRun(harness)
        XCTAssertNotNil(harness.model.state.failure)
        harness.model.send(.failureDismissed)
        XCTAssertNil(harness.model.state.failure)

        harness.model.send(.connectRequested(F.adapter()))
        XCTAssertEqual(harness.model.state.phase, .connecting)
        XCTAssertNil(harness.model.state.failure)
        _ = await waitForIdleAfterRun(harness)
    }

    // MARK: Re-entrancy and stopping

    func testStartingWhileNotIdleIsRejected() async {
        let harness = makeHarness(vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter()))
        harness.model.send(.connectRequested(F.adapter(transport: .usbSerial)))
        XCTAssertEqual(harness.model.state.adapter, F.adapter())
        _ = await waitForPhase(harness, .recording)
        harness.model.send(.connectRequested(F.adapter(transport: .usbSerial)))
        harness.model.send(.stopRequested)
        _ = await waitForIdleAfterRun(harness)
        XCTAssertEqual(harness.linkPort.openedAdapters, [F.adapter()])
        XCTAssertEqual(harness.link.closeCount, 1)
    }

    func testStopRequestedWhileIdleIsIgnored() {
        let harness = makeHarness()
        harness.model.send(.stopRequested)
        XCTAssertEqual(harness.model.state, DriveSessionState())
    }

    func testStopDuringConnectingNeverStartsASession() async {
        let harness = makeHarness(vehicles: [F.vehicle()])
        harness.model.send(.connectRequested(F.adapter()))
        harness.model.send(.stopRequested)
        XCTAssertEqual(harness.model.state.phase, .stopping)
        let idle = await waitForPhase(harness, .idle)
        XCTAssertTrue(idle)
        XCTAssertNil(harness.model.state.failure)
        let begun = harness.sessions.begun
        XCTAssertTrue(begun.isEmpty)
        XCTAssertEqual(harness.link.closeCount, 1)
        XCTAssertTrue(harness.inhibitor.calls.isEmpty)
    }

    // MARK: Launch recovery

    func testAppLaunchedFinishesUnfinishedSessionsAndNotifies() async {
        let sessions = DriveFlowSessionRepository()
        var recovered = F.session()
        recovered.endedAt = F.epoch
        recovered.endReason = .appTerminated
        sessions.configure(unfinishedResult: [recovered, recovered])
        let harness = makeHarness(sessions: sessions)
        harness.model.send(.appLaunched)
        let done = await F.waitUntil { harness.model.state.recoveredSessionCount == 2 }
        XCTAssertTrue(done)
        XCTAssertEqual(harness.ended.sessions.count, 2)
        let calls = sessions.unfinishedCalls
        XCTAssertEqual(calls, 1)
    }

    func testAppLaunchedFailureIsReported() async {
        let sessions = DriveFlowSessionRepository()
        sessions.configure(failFinishUnfinished: true)
        let harness = makeHarness(sessions: sessions)
        harness.model.send(.appLaunched)
        let done = await F.waitUntil { harness.model.state.failure != nil }
        XCTAssertTrue(done)
        XCTAssertEqual(harness.model.state.failure, DriveSessionFailure(phase: .idle, kind: .store))
    }
}
