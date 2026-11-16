import XCTest
@testable import ProjectZD8

/// LiveTelemetryState.receivedResponseCount が応答の受信ごとに増え、新しいセッションで0に戻ることを検証します。
@MainActor
final class LiveTelemetryModelReceivedResponseCountTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 開始直後の件数は0です。
    ///
    /// 責務: 応答を受ける前の件数が0であることを確認します。
    func testCountIsZeroBeforeAnyResponse() async {
        let fixture = makeFixture()
        fixture.start()
        await fixture.telemetry.waitForSentRequests(1)

        XCTAssertEqual(fixture.model.state.receivedResponseCount, 0)
    }

    /// 応答を受け取るたびに1ずつ増えます。
    ///
    /// 責務: 初回周回の2件の後、表示更新の間隔を空けて1件ずつ応答を返し、件数が2・3・4・5と増えることを確認します。
    func testCountIncreasesByOneForEachResponse() async {
        let fixture = await startLoaded()
        XCTAssertEqual(fixture.model.state.receivedResponseCount, 2)

        for expected in 3...5 {
            fixture.clock.advance(byNanoseconds: LiveTelemetryDisplayRefreshThrottle.minimumIntervalNanoseconds)
            await fixture.telemetry.release(.responded([1]))
            guard await fixture.waitUntil("件数 \(expected)", condition: { fixture.model.state.receivedResponseCount == expected }) else { return }
            XCTAssertEqual(fixture.model.state.receivedResponseCount, expected)
        }
    }

    /// 新しいセッションの開始で0に戻り、前のセッションの件数を引き継ぎません。
    ///
    /// 責務: 停止後に再開始した直後の件数が0で、再開始後の応答が新しいセッションの件数だけを数えることを確認します。
    func testCountResetsWhenNewSessionStarts() async {
        let fixture = await startLoaded()
        XCTAssertEqual(fixture.model.state.receivedResponseCount, 2)
        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        fixture.start()
        XCTAssertEqual(fixture.model.state.receivedResponseCount, 0)
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.waitUntil("再開始後の読み込み済み") { fixture.model.state.phase == .loaded }

        XCTAssertEqual(fixture.model.state.receivedResponseCount, 2)
    }

    /// 応答の無い結果(通信失敗・応答期限切れ)では増えません。
    ///
    /// 責務: 応答1件を受けた後に、失敗系の結果で一時停止へ移っても件数が応答の分だけであることを確認します。
    func testNonResponseOutcomesDoNotIncreaseCount() async {
        let outcomes: [OBDPIDRequestTransportOutcome] = [.transportFailure, .timedOut]
        for outcome in outcomes {
            let fixture = await startLoaded()
            await fixture.telemetry.release(.responded([1]))
            await fixture.telemetry.waitForSentRequests(4)
            fixture.clock.advance(byNanoseconds: AcquisitionStallPolicy.stallThresholdNanoseconds)
            await fixture.telemetry.release(outcome)
            guard await fixture.waitUntil("一時停止", condition: { fixture.model.state.phase == .paused }) else { return }

            XCTAssertEqual(fixture.model.state.receivedResponseCount, 3, "\(outcome)")
            await fixture.tearDown()
            self.fixture = nil
        }
    }

    /// 非対応や分類不能の結果でも増えません。
    ///
    /// 責務: 応答でない結果を返した後に1件だけ応答を返すと、件数がその1件の分だけ増えることを確認します。
    func testUnsupportedAndUnclassifiedOutcomesDoNotIncreaseCount() async {
        let fixture = await startLoaded()
        await fixture.telemetry.release(.unsupported)
        await fixture.telemetry.release(.unclassifiedResponse)
        await fixture.telemetry.waitForSentRequests(5)
        fixture.clock.advance(byNanoseconds: LiveTelemetryDisplayRefreshThrottle.minimumIntervalNanoseconds)
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("件数 3") { fixture.model.state.receivedResponseCount >= 3 }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.model.state.receivedResponseCount, 3)
    }

    /// PID 2件だけを取得対象にしたモデル部品を生成して保持します。
    ///
    /// 責務: 記録ポートなしのモデル部品を組み立て、tearDown で片付けられるよう保持します。
    /// - Returns: 未開始のモデル部品。
    private func makeFixture() -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x31, 0xA6]))
        self.fixture = fixture
        return fixture
    }

    /// 開始して初回周回の2件へ応答を返し、読込み済みにします。
    ///
    /// 責務: 読み込み済みになるまで上限付きで待ちます。
    /// - Returns: 読込み済みのモデル部品。
    private func startLoaded() async -> LiveTelemetryModelFixture {
        let fixture = makeFixture()
        fixture.start()
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        return fixture
    }
}
