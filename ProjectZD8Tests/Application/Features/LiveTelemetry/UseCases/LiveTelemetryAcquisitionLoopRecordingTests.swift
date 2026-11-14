import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループと記録ポートの連携、記録失敗時の終了、記録ポートなしの経路を検証します。
@MainActor
final class LiveTelemetryAcquisitionLoopRecordingTests: XCTestCase {
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 記録の開始が最初の要求より前に行われ、基準周回の要求順が渡されます。
    ///
    /// 責務: 記録開始入力の定義・capability・基準要求順と、開始が最初の呼び出しであることを確認します。
    func testRecordingStartPrecedesFirstRequestWithBaseOrder() async {
        let fixture = makeFixture()
        let definitions = LiveTelemetryTestDefinitions.standard([0x05, 0x0C])
        _ = await fixture.start(definitions: definitions)
        await fixture.waitForSentRequests(1)

        let calls = await fixture.recorder?.calls ?? []
        let input = await fixture.recorder?.startInputs.first
        XCTAssertEqual(calls.first, .start(generation: 1))
        XCTAssertEqual(input?.definitions, definitions)
        XCTAssertEqual(input?.capabilities, LiveTelemetryTestDefinitions.capabilities(for: definitions))
        XCTAssertEqual(input?.orderedRequests, [0x0C, 0x05].map(LiveTelemetryTestDefinitions.request))
        XCTAssertEqual(fixture.telemetry.sentRequests, [LiveTelemetryTestDefinitions.request(0x0C)])
    }

    /// 要求1件ごとの結果が周回・要求順・Transport結果・値の評価・経過付きで記録されます。
    ///
    /// 責務: 正応答の範囲内・範囲外とタイムアウトを記録へ渡す内容と、周回の開始・終了の記録を確認します。
    func testEachRequestResultIsRecordedWithRoundIdentity() async {
        let fixture = makeFixture()
        let definitions = [0x0C, 0x0D].map { LiveTelemetryTestDefinitions.standard($0, maximumValue: 100) }
        _ = await fixture.start(definitions: definitions)
        await fixture.waitForSentRequests(1)
        fixture.clock.advance(byNanoseconds: 1_500)
        await fixture.telemetry.release(.responded([50]))
        await fixture.telemetry.release(.responded([200]))
        await fixture.telemetry.release(.timedOut)
        await fixture.waitForSentRequests(4)

        let calls = await fixture.recorder?.calls ?? []
        let results = await fixture.recorder?.recordedResults ?? []
        XCTAssertEqual(results.map(\.batchOrdinal), [0, 0, 1])
        XCTAssertEqual(results.map(\.requestOrdinal), [0, 1, 0])
        XCTAssertEqual(results.map(\.outcome), [.responded([50]), .responded([200]), .timedOut])
        XCTAssertEqual(results.map(\.valueOutcome), [.decodedValid, .invalidValue, .notEvaluated])
        XCTAssertEqual(results.map(\.elapsedNanoseconds), [1_500, 0, 0])
        XCTAssertEqual(results.map(\.generation), [1, 1, 1])
        XCTAssertTrue(calls.contains(.finishRound(generation: 1, batchOrdinal: 0)))
        let rounds = await fixture.recorder?.roundInputs ?? []
        XCTAssertEqual(rounds.first?.startedAt, LiveTelemetryAcquisitionLoopFixture.fixedNow)
    }

    /// 記録の開始に失敗すると要求を1件も送らずに保存失敗で終わります。
    ///
    /// 責務: 開始失敗を成功扱いせず、記録の終了とendSessionを行うことを確認します。
    func testStartFailureEndsAsRecordingFailedWithoutRequests() async {
        let (fixture, termination) = await runUntilTermination(failing: .start, responses: 0)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
        let calls = await fixture.recorder?.calls
        XCTAssertEqual(calls, [.start(generation: 1), .finish(generation: 1, reason: .acquisitionFailed)])
    }

    /// 周回開始の記録に失敗すると要求を送らずに保存失敗で終わります。
    ///
    /// 責務: 周回開始の失敗を成功扱いしないことを確認します。
    func testBeginRoundFailureEndsAsRecordingFailedWithoutRequests() async {
        let (fixture, termination) = await runUntilTermination(failing: .beginRound, responses: 0)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// 要求結果の記録に失敗すると次の要求を送らずに保存失敗で終わります。
    ///
    /// 責務: 記録の失敗を成功扱いせず、取得を止めることを確認します。
    func testRecordFailureEndsAsRecordingFailed() async {
        let (fixture, termination) = await runUntilTermination(failing: .record, responses: 1)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 1)
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .acquisitionFailed)])
    }

    /// 周回終了の記録に失敗すると次の周回へ進まずに保存失敗で終わります。
    ///
    /// 責務: 周回終了の失敗を成功扱いしないことを確認します。
    func testFinishRoundFailureEndsAsRecordingFailed() async {
        let (fixture, termination) = await runUntilTermination(failing: .finishRound, responses: 2)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 2)
    }

    /// flushに失敗すると、次の受信の後で次の要求を送らずに保存失敗で終わります。
    ///
    /// 責務: flushの失敗が世代に保持され、応答後に取得を止めることを確認します。
    func testFlushFailureEndsAsRecordingFailedAfterNextResult() async {
        let fixture = makeFixture(failing: .flush)
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]))
        await fixture.waitForSentRequests(1)

        await fixture.loop.flush(.backgroundTransition)
        await fixture.telemetry.release(.responded([1]))
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 1)
        let calls = await fixture.recorder?.calls ?? []
        XCTAssertTrue(calls.contains(.flush(.backgroundTransition, generation: 1)))
    }

    /// 記録の終了に失敗すると、停止の結果も保存失敗になります。
    ///
    /// 責務: 終了処理の失敗を停止の成功として返さないことを確認します。
    func testFinishFailureTurnsStopIntoRecordingFailed() async {
        let fixture = makeFixture(failing: .finish)
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C]))
        await fixture.waitForSentRequests(1)

        let termination = await fixture.loop.stop()

        XCTAssertEqual(termination, .recordingFailed)
        _ = await fixture.waitForTermination(of: collector)
        XCTAssertEqual(collector.termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// 記録の終了に失敗すると、無応答による終了も保存失敗になります。
    ///
    /// 責務: 取得側の終了理由より記録の失敗を優先することを確認します。
    func testFinishFailureTurnsNoVehicleResponseIntoRecordingFailed() async {
        let (_, termination) = await runUntilTermination(failing: .finish, responses: 0, silentResponses: 1)

        XCTAssertEqual(termination, .recordingFailed)
    }

    /// 定義とcapabilityの件数が揃わなければ記録を開始せず、要求も送りません。
    ///
    /// 責務: 不正な開始入力を保存失敗として扱うことを確認します。
    func testMismatchedCapabilitiesEndAsRecordingFailedWithoutStart() async {
        let fixture = makeFixture()
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C]), capabilities: [])

        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .recordingFailed)
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        let calls = await fixture.recorder?.calls
        XCTAssertEqual(calls, [.finish(generation: 1, reason: .acquisitionFailed)])
    }

    /// flushの契機と現在の世代が記録ポートへ渡り、成功すれば取得を続けます。
    ///
    /// 責務: flush成功後も次の要求が送られることを確認します。
    func testSuccessfulFlushPassesTriggerAndKeepsPolling() async {
        let fixture = makeFixture()
        _ = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C]))
        await fixture.waitForSentRequests(1)

        await fixture.loop.flush(.segmentEnded)
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitForSentRequests(2)

        let calls = await fixture.recorder?.calls ?? []
        XCTAssertTrue(calls.contains(.flush(.segmentEnded, generation: 1)))
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 2)
    }

    /// 取得が動いていない間のflushは記録ポートへ届きません。
    ///
    /// 責務: 世代の無いflushを何もしない操作として扱うことを確認します。
    func testFlushWithoutRunningGenerationDoesNothing() async {
        let fixture = makeFixture()

        await fixture.loop.flush(.sessionEnded)

        let calls = await fixture.recorder?.calls
        XCTAssertEqual(calls, [])
    }

    /// 記録ポートなしでもループが回り、数値化した観測が流れます。
    ///
    /// 責務: 記録しない経路で取得対象の確定と観測の送出が行われることを確認します。
    func testLoopWithoutRecorderStillStreamsSamples() async {
        let fixture = LiveTelemetryAcquisitionLoopFixture(recorder: nil)
        self.fixture = fixture
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]), capabilities: [])

        await fixture.telemetry.answer(3) { .responded([$0.pid]) }
        await LiveTelemetryBoundedWaiter.waitUntil("観測3件") { collector.samples.count >= 3 }

        XCTAssertFalse(fixture.loop.recordsAcquisition)
        XCTAssertEqual(collector.samples.map(\.value), [12, 13, 12])
        XCTAssertEqual(collector.samples.map(\.observedAt), Array(repeating: LiveTelemetryAcquisitionLoopFixture.fixedNow, count: 3))
        XCTAssertEqual(collector.confirmedTargets.count, 1)
        XCTAssertNil(collector.termination)
        XCTAssertTrue(makeFixture().loop.recordsAcquisition)
    }

    /// 記録ポートのスパイ付きの部品を生成して後片付けの対象にします。
    ///
    /// 責務: 失敗指定付きの記録ポートを持つループ部品を返します。
    /// - Parameter failurePoint: 失敗させる記録の呼び出し。
    /// - Returns: ループ部品。
    private func makeFixture(failing failurePoint: LiveTelemetryRecordingFailurePoint? = nil) -> LiveTelemetryAcquisitionLoopFixture {
        let fixture = LiveTelemetryAcquisitionLoopFixture(recorder: LiveTelemetryRecordingPortSpy(failing: failurePoint))
        if self.fixture == nil { self.fixture = fixture }
        return fixture
    }

    /// 2PIDの取得を指定件数の正応答と無応答で進め、終了を待ちます。
    ///
    /// 責務: 記録の失敗指定付きでループを開始し、応答を解放して終了理由を返します。
    /// - Parameters:
    ///   - failurePoint: 失敗させる記録の呼び出し。
    ///   - responses: 返す正応答の件数。
    ///   - silentResponses: 正応答の後に返すタイムアウトの件数。
    /// - Returns: ループ部品と終了理由。
    private func runUntilTermination(
        failing failurePoint: LiveTelemetryRecordingFailurePoint,
        responses: Int,
        silentResponses: Int = 0
    ) async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionTermination?) {
        let fixture = makeFixture(failing: failurePoint)
        let definitions = LiveTelemetryTestDefinitions.standard(silentResponses > 0 ? [0x0C] : [0x0C, 0x0D])
        let collector = await fixture.start(definitions: definitions)
        await fixture.telemetry.answer(responses) { _ in .responded([1]) }
        await fixture.telemetry.answer(silentResponses) { _ in .timedOut }
        return (fixture, await fixture.waitForTermination(of: collector))
    }
}
