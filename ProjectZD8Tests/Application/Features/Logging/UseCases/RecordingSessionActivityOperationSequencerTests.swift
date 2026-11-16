import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityOperationSequencer` の世代管理・直列実行・世代と表示状態による実行判定・失敗後の継続を検証します。
///
/// 仕様: U5 受け入れ条件 5〜7・9(B13)。開始・更新は世代が続いている時だけ、終了は必ず受け付けて先の開始の完了後に実行し、
/// 古い世代の操作は捨てます。待機はすべて上限付きです。
@MainActor
final class RecordingSessionActivityOperationSequencerTests: XCTestCase {
    /// 境界の偽物です。
    private var activity: SessionActivityPortSpy!
    /// 診断の偽物です。
    private var diagnostics: RecordingSessionActivityDiagnosticsSpy!
    /// 検証対象です。
    private var sequencer: RecordingSessionActivityOperationSequencer!
    /// `didStart` が呼ばれた回数です。
    private var didStartCount = 0
    /// `didEnd` が呼ばれた回数です。
    private var didEndCount = 0

    /// 責務: テストごとに偽物と検証対象を作り直します。
    override func setUp() async throws {
        try await super.setUp()
        activity = SessionActivityPortSpy()
        diagnostics = RecordingSessionActivityDiagnosticsSpy()
        sequencer = RecordingSessionActivityOperationSequencer(activity: activity, diagnostics: diagnostics)
        didStartCount = 0
        didEndCount = 0
    }

    /// 責務: 保留中の開始を再開させ、残った操作を上限付きで片付けます。
    override func tearDown() async throws {
        activity?.releaseAllHeldStarts()
        if sequencer != nil { await waitForOperations() }
        sequencer = nil
        activity = nil
        diagnostics = nil
        try await super.tearDown()
    }

    /// 表示内容を作ります。
    ///
    /// 責務: 開始時刻と車速で区別できる内容を返します。
    /// - Parameters:
    ///   - startedAt: 1970年からの秒数で表した開始時刻。
    ///   - speed: 車速。
    /// - Returns: 表示内容。
    private func content(startedAt: TimeInterval = 1_000, speed: Double = 10) -> RecordingSessionActivityContent {
        var telemetry = LiveTelemetryState()
        telemetry.phase = .loaded
        telemetry.samples = [OBDPIDSample(
            request: RecordingSessionActivityContent.vehicleSpeedRequest,
            nameKey: "speed", value: speed, unit: "km/h", observedAt: Date(timeIntervalSince1970: startedAt)
        )]
        return RecordingSessionActivityContent(
            telemetry: telemetry, vehicleName: nil, startedAt: Date(timeIntervalSince1970: startedAt), vehiclePhotoFileName: nil
        )
    }

    /// 受け付けた操作の完了を上限付きで待ちます。
    ///
    /// 責務: 終わらない場合は `XCTFail` で失敗させます。
    private func waitForOperations(file: StaticString = #filePath, line: UInt = #line) async {
        let sequencer = sequencer!
        _ = await LiveTelemetryBoundedWaiter.value("操作の完了", file: file, line: line) { await sequencer.waitForPendingOperations() }
    }

    /// 開始を受け付けます。
    ///
    /// 責務: `didStart` の回数を数える開始を受け付けます。
    private func enqueueStart(_ content: RecordingSessionActivityContent, generation: Int) {
        sequencer.enqueueStart(content, generation: generation) { [weak self] in self?.didStartCount += 1 }
    }

    /// 終了を受け付けます。
    ///
    /// 責務: `didEnd` の回数を数える終了を受け付けます。
    private func enqueueEnd(_ content: RecordingSessionActivityContent) {
        sequencer.enqueueEnd(content) { [weak self] in self?.didEndCount += 1 }
    }

    /// 世代はセッションごとに1つずつ進み、続いている世代だけが live です。終わらせると続いている世代は無くなります。
    ///
    /// 責務: `beginSession`・`endSession`・`currentGeneration`・`isLive` の分岐を確認します。
    func testGenerationLifecycle() {
        XCTAssertNil(sequencer.currentGeneration)
        let first = sequencer.beginSession()
        XCTAssertEqual(sequencer.currentGeneration, first)
        XCTAssertTrue(sequencer.isLive(first))
        let second = sequencer.beginSession()
        XCTAssertEqual(second, first + 1)
        XCTAssertFalse(sequencer.isLive(first), "新しいセッションを始めたら古い世代は live でない")
        XCTAssertTrue(sequencer.isLive(second))

        sequencer.endSession()

        XCTAssertNil(sequencer.currentGeneration)
        XCTAssertFalse(sequencer.isLive(second))
        XCTAssertEqual(sequencer.beginSession(), second + 1, "終わらせた後も世代は使い回さない")
    }

    /// 続いている世代で表示が出ていなければ開始し、`didStart` を1回呼びます。
    ///
    /// 責務: 開始が境界へ届き、表示中になり、`didStart` が1回であることを確認します。
    func testStartRunsWhenLiveAndNotPresenting() async {
        let generation = sequencer.beginSession()
        enqueueStart(content(), generation: generation)
        await waitForOperations()
        XCTAssertEqual(activity.startedContents, [content()])
        XCTAssertEqual(didStartCount, 1)
    }

    /// 既に表示が出ていれば開始を送らず、`didStart` も呼びません。
    ///
    /// 責務: 表示中の開始で境界の呼び出しが0件であることを確認します。
    func testStartSkippedWhilePresenting() async {
        activity.isPresenting = true
        enqueueStart(content(), generation: sequencer.beginSession())
        await waitForOperations()
        XCTAssertEqual(activity.calls, [])
        XCTAssertEqual(didStartCount, 0)
    }

    /// 古い世代の開始と、実行前にセッションが終わった開始は捨てます。
    ///
    /// 責務: 次の世代が始まった後の古い世代の開始と、受け付け直後の `endSession` の後の開始で、境界の呼び出しが0件であることを確認します(受け入れ条件 5・6)。
    func testStaleOrEndedGenerationStartIsDropped() async {
        let old = sequencer.beginSession()
        _ = sequencer.beginSession()
        enqueueStart(content(), generation: old)
        await waitForOperations()

        let ended = sequencer.beginSession()
        enqueueStart(content(), generation: ended)
        sequencer.endSession()
        await waitForOperations()

        XCTAssertEqual(activity.calls, [])
        XCTAssertEqual(didStartCount, 0)
    }

    /// 更新は続いている世代の時だけ送り、古い世代・終わったセッションの更新は捨てます。
    ///
    /// 責務: live の更新1件だけが境界へ届くことを確認します(受け入れ条件 6)。
    func testUpdateRunsOnlyForLiveGeneration() async {
        let old = sequencer.beginSession()
        let live = sequencer.beginSession()
        sequencer.enqueueUpdate(content(speed: 1), generation: old)
        sequencer.enqueueUpdate(content(speed: 2), generation: live)
        await waitForOperations()
        sequencer.endSession()
        sequencer.enqueueUpdate(content(speed: 3), generation: live)
        await waitForOperations()

        XCTAssertEqual(activity.updatedContents, [content(speed: 2)])
    }

    /// 終了は世代に関係なく受け付け、表示が出ていれば閉じて `didEnd` を呼び、出ていなければ送りません。
    ///
    /// 責務: セッションを終わらせた後でも表示中なら終了が届き、表示が無ければ届かないことを確認します(受け入れ条件 5)。
    func testEndRunsRegardlessOfGenerationOnlyWhenPresenting() async {
        sequencer.endSession()
        enqueueEnd(content())
        await waitForOperations()
        XCTAssertEqual(activity.endedContents, [], "表示が無ければ送らない")
        XCTAssertEqual(didEndCount, 0)

        activity.isPresenting = true
        enqueueEnd(content(speed: 5))
        await waitForOperations()
        XCTAssertEqual(activity.endedContents, [content(speed: 5)])
        XCTAssertFalse(activity.isPresenting)
        XCTAssertEqual(didEndCount, 1)
    }

    /// 終了は先に受け付けた開始の完了を待ってから実行し、開始の最中に終わったセッションの表示を直ちに閉じます。
    ///
    /// 責務: 開始を保留した間は終了が届かず、再開後に「開始 → 終了」の順で届いて表示中でなくなることを確認します(受け入れ条件 5)。
    func testEndWaitsForInFlightStart() async {
        activity.holdsStart = true
        let generation = sequencer.beginSession()
        enqueueStart(content(), generation: generation)
        await LiveTelemetryBoundedWaiter.waitUntil("開始の保留") { activity.heldStartCount == 1 }
        sequencer.endSession()
        enqueueEnd(content(speed: 9))
        await LiveTelemetryBoundedWaiter.settle(polls: 5)
        XCTAssertEqual(activity.endedContents, [], "開始の完了前に終了を送らない")

        activity.releaseHeldStart()
        await waitForOperations()

        XCTAssertEqual(activity.calls, [.start(content()), .end(content(speed: 9))])
        XCTAssertFalse(activity.isPresenting)
    }

    /// 操作の失敗は診断へ1件ずつ残し、後続の操作は続けて実行します。
    ///
    /// 責務: 開始・更新・終了の失敗が順に `[.start, .update, .end]` で残り、失敗の後の操作も境界へ届き、`didStart`/`didEnd` が呼ばれないことを確認します
    /// (受け入れ条件 7)。
    func testFailuresAreRecordedAndLaterOperationsContinue() async {
        let generation = sequencer.beginSession()
        activity.startError = SessionActivityPortError.notAuthorized
        enqueueStart(content(), generation: generation)
        activity.updateError = SessionActivityPortError.notPresenting
        sequencer.enqueueUpdate(content(speed: 2), generation: generation)
        await waitForOperations()
        activity.isPresenting = true
        activity.endError = SessionActivityPortError.notPresenting
        enqueueEnd(content(speed: 3))
        await waitForOperations()

        XCTAssertEqual(diagnostics.failedOperations, [.start, .update, .end])
        XCTAssertEqual(activity.calls, [.start(content()), .update(content(speed: 2)), .end(content(speed: 3))])
        XCTAssertEqual(didStartCount, 0)
        XCTAssertEqual(didEndCount, 0)
    }

    /// 何も受け付けていなければ、完了待ちは直ちに戻ります。
    ///
    /// 責務: 操作なしの `waitForPendingOperations()` が上限内に戻ることを確認します。
    func testWaitWithoutOperationsReturns() async {
        await waitForOperations()
        XCTAssertEqual(activity.calls, [])
    }
}
