import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` で、表示の開始が終わる前にセッションが終わっても表示が残らず、
/// 古いセッションの開始が新しいセッションの表示を上書きしないことを検証します。
///
/// 仕様: U5 受け入れ条件 5・6・8(B13)。開始の最中は境界の偽物の開始を保留して再現します(待機はすべて上限付き)。
@MainActor
final class RecordingSessionActivityUseCaseRaceTests: XCTestCase {
    /// テスト中に組み立てた準備です。終了時に保留中の開始を再開させます。
    private var harnesses: [RecordingSessionActivityUseCaseHarness] = []

    /// 責務: 保留中の開始を再開させ、残った操作を上限付きで片付けます。
    override func tearDown() async throws {
        for harness in harnesses {
            harness.activity.releaseAllHeldStarts()
            await waitForOperations(harness)
        }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 準備を組み立て、終了処理の対象に加えます。
    ///
    /// 責務: 前面にいる準備を返します。
    /// - Returns: 準備。
    private func makeHarness() -> RecordingSessionActivityUseCaseHarness {
        let harness = RecordingSessionActivityUseCaseHarness()
        harnesses.append(harness)
        return harness
    }

    /// 受け付けた境界操作の完了を上限付きで待ちます。
    ///
    /// 責務: 操作が終わらない場合は待ち続けず `XCTFail` で失敗させます。
    /// - Parameter harness: 準備。
    private func waitForOperations(_ harness: RecordingSessionActivityUseCaseHarness, file: StaticString = #filePath, line: UInt = #line) async {
        let useCase = harness.useCase!
        _ = await LiveTelemetryBoundedWaiter.value("境界操作の完了", file: file, line: line) { await useCase.waitForPendingOperations() }
    }

    /// 開始イベントの直後(開始の操作が実行される前)に終了イベントが来ても、表示は残りません。
    ///
    /// 責務: 記録中と待機を続けて渡し、操作の完了後に表示中でないことを確認します(受け入れ条件 5)。
    func testEndRightAfterStartEventLeavesNoPresentation() async {
        let harness = makeHarness()

        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 10))
        harness.useCase.telemetryStateDidChange(harness.state(.idle, speed: 10))
        await waitForOperations(harness)

        XCTAssertFalse(harness.activity.isPresenting, "終わったセッションの表示が残った: \(harness.activity.calls)")
    }

    /// 開始の操作の最中(境界の開始がまだ戻らない間)にセッションが終わっても、開始の完了後に表示は残りません。
    ///
    /// 責務: 開始を保留した状態で待機を渡し、開始を再開させた後に表示中でなく、出した表示は最終内容で終了されることを確認します
    /// (受け入れ条件 5・8)。
    func testEndWhileStartIsInFlightLeavesNoPresentation() async {
        let harness = makeHarness()
        harness.activity.holdsStart = true
        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 10))
        await LiveTelemetryBoundedWaiter.waitUntil("開始の保留") { harness.activity.heldStartCount == 1 }

        harness.useCase.telemetryStateDidChange(harness.state(.idle, speed: 10))
        harness.activity.releaseHeldStart()
        await waitForOperations(harness)

        XCTAssertFalse(harness.activity.isPresenting, "終わったセッションの表示が残った: \(harness.activity.calls)")
        XCTAssertEqual(harness.activity.endedContents.last?.statusKey, "live_activity.status.ended")
    }

    /// 古いセッションの開始が遅れて終わっても、新しいセッションの表示を上書きせず、新しいセッションの表示が出たままになります。
    ///
    /// 責務: 1件目の開始を保留したまま1件目を終え2件目を始め、開始を再開させた後、表示中で、
    /// 最後に境界へ渡した内容が2件目の開始時刻のもので、その後に終了が届いていないことを確認します(受け入れ条件 6・8)。
    func testLateStartOfOldSessionDoesNotOverrideNewSession() async throws {
        let harness = makeHarness()
        harness.activity.holdsStart = true
        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 10))
        await LiveTelemetryBoundedWaiter.waitUntil("1件目の開始の保留") { harness.activity.heldStartCount == 1 }
        harness.useCase.telemetryStateDidChange(harness.state(.idle, speed: 10))
        harness.activity.holdsStart = false
        harness.currentDate = harness.currentDate.addingTimeInterval(60)
        let secondStartedAt = harness.currentDate
        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 20))

        harness.activity.releaseHeldStart()
        await waitForOperations(harness)

        XCTAssertTrue(harness.activity.isPresenting, "新しいセッションの表示が出ていない: \(harness.activity.calls)")
        let last = try XCTUnwrap(harness.activity.calls.last)
        switch last {
        case let .start(content), let .update(content):
            XCTAssertEqual(content.startedAt, secondStartedAt, "最後の表示が古いセッションのもの: \(harness.activity.calls)")
        case .end, .endOrphanedPresentations:
            XCTFail("新しいセッションの表示が終了された: \(harness.activity.calls)")
        }
    }

    /// 開始の最中に終わったセッションの後、新しいセッションの開始は通常どおり表示されます。
    ///
    /// 責務: 開始を保留中に終了・再開させた後、次のセッションの記録中で表示中になり、その表示の開始時刻が次のセッションのものであることを確認します(受け入れ条件 5・6)。
    func testNextSessionStartsNormallyAfterRacedEnd() async throws {
        let harness = makeHarness()
        harness.activity.holdsStart = true
        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 10))
        await LiveTelemetryBoundedWaiter.waitUntil("開始の保留") { harness.activity.heldStartCount == 1 }
        harness.useCase.telemetryStateDidChange(harness.state(.idle, speed: 10))
        harness.activity.releaseAllHeldStarts()
        await waitForOperations(harness)

        harness.currentDate = harness.currentDate.addingTimeInterval(60)
        await harness.send(harness.state(.loaded, speed: 30))

        XCTAssertTrue(harness.activity.isPresenting)
        XCTAssertEqual(harness.activity.startedContents.last?.startedAt, harness.currentDate)
    }
}
