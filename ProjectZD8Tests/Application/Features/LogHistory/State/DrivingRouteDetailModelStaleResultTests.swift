import Darwin
import Foundation
import XCTest
@testable import ProjectZD8

/// 計算まで終わった古い読み込みの結果が、切り替え・閉じる・アカウントの変化の後に届いても反映されないこと(世代の照合)を検証します。
///
/// 読み込みのタスクが取り消されると計算の段階で結果が捨てられるため、取り消しより前に計算を終わらせます。
/// 古い読み込みが計算の完了を待っている間にメインを短く止め(上限 0.5 秒)、計算を終えさせてから操作を送ります。
/// こうすると、古い結果が届く時には取り消しが効かず、世代の照合だけが古い結果を止めます。
@MainActor
final class DrivingRouteDetailModelStaleResultTests: XCTestCase {
    /// 古い読み込みの点の数です(計算に時間が掛かり、メインを譲る間に計算が終わらない大きさ)。
    private static let staleSampleCount = 5_000
    /// 古い読み込みを計算の完了待ちまで進めるために、メインを譲る回数です。
    private static let yieldCount = 5

    /// モデルと部品の組です。
    private var harness = DrivingRouteDetailModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.gate.releaseAll()
        try await super.tearDown()
    }

    /// 別のセッションへ切り替えた後に古い結果が届いても、新しいセッションの読み込み中のままです。
    ///
    /// 責務: 計算を終えた前のセッションの結果が、切り替え後の状態(新しい ID の `loading`)を上書きしないことを確認します。
    func testStaleResultAfterSwitchingSessionIsDiscarded() async throws {
        let previous = DrivingRouteTestValues.session()
        let next = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: previous.id, sampleCount: Self.staleSampleCount))
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: next.id, sampleCount: 3))
        harness.gate.hold(next.id)
        try await startLoadAndLetComputationFinish(previous)

        harness.model.send(.sessionShown(next))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: next.id, phase: .loading))
        harness.gate.release(next.id)
        let content = try await harness.waitForLoadedContent(next.id)
        XCTAssertEqual(content.geometry.polylines.first?.coordinates.count, 3)
    }

    /// 閉じた後に古い結果が届いても、初期状態のままです。
    ///
    /// 責務: 計算を終えた結果が、`sessionHidden` の後の `idle` を上書きしないことを確認します。
    func testStaleResultAfterHidingIsDiscarded() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: Self.staleSampleCount))
        try await startLoadAndLetComputationFinish(session)

        harness.model.send(.sessionHidden(session.id))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: nil, phase: .idle))
    }

    /// アカウントが変わった後に古い結果が届いても、新しいアカウントでの読み込み中のままです。
    ///
    /// 責務: 計算を終えた前のアカウントの結果が、読み直し中の `loading` を上書きしないことを確認します。
    func testStaleResultAfterAccountChangeIsDiscarded() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: Self.staleSampleCount))
        try await startLoadAndLetComputationFinish(session)
        harness.gate.hold(session.id)

        harness.model.send(.accountIdentifierChanged("other-account"))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: session.id, phase: .loading))
        XCTAssertEqual(harness.recorder.calls.last?.accountIdentifier, "other-account")
    }

    /// 読み込みを始め、古い読み込みが計算の完了を待つ所まで進めてから、計算を終えさせます。
    ///
    /// 責務: 再開の記録を期限つきで待ち、数回だけメインを譲って古い読み込みを計算の完了待ちまで進め、
    /// まだ反映されていないことを確かめてから、メインを譲らずに短く止めて、メインの外の計算を取り消しより前に終わらせます。
    /// - Parameter session: 読み込むセッション。
    /// - Throws: 期限内に再開が記録されなければテスト失敗。
    private func startLoadAndLetComputationFinish(_ session: ConnectionSession) async throws {
        harness.model.send(.accountIdentifierChanged(DrivingRouteDetailModelHarness.account))
        harness.model.send(.sessionShown(session))
        _ = try await harness.waitForResumption(session.id)
        for _ in 0..<Self.yieldCount {
            await Task.yield()
        }
        XCTAssertEqual(harness.model.state.phase, .loading, "前提: 古い結果が操作より先に反映されてしまいました")
        blockMainActorBriefly()
    }

    /// メインを譲らずに 0.5 秒だけ止めます。
    ///
    /// 責務: 計算を終えた古い読み込みが、この後に送る操作より先にメインで再開しないようにします。
    private func blockMainActorBriefly() {
        usleep(500_000)
    }
}
