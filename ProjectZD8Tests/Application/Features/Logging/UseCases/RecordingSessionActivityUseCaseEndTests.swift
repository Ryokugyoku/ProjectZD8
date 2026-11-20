import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` の終了と、境界の失敗が外へ出ないことのテストです。
@MainActor
final class RecordingSessionActivityUseCaseEndTests: XCTestCase {
    /// 責務: セッションが待機へ移ると最終状態を載せて終了を呼ぶことを確認します。
    func testIdleEndsActivityWithFinalContent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 42))
        await harness.send(harness.state(.idle, speed: 42))
        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.activity.endedContents[0].statusKey, "live_activity.status.ended")
        XCTAssertEqual(harness.activity.endedContents[0].vehicleSpeed, .value(42))
        XCTAssertFalse(harness.activity.isPresenting)
    }

    /// 責務: 取得が失敗へ移ると失敗状態を載せて終了を呼ぶことを確認します。
    func testFailedEndsActivityWithFailedStatus() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 42))
        await harness.send(harness.state(.failed, speed: 42))
        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.activity.endedContents[0].statusKey, "live_activity.status.failed")
        XCTAssertEqual(harness.activity.endedContents[0].statusTone, .warning)
    }

    /// 責務: 開始が throw しても例外を出さず、診断へ開始として1件残し、記録はそのまま続いて後の状態変化で診断が増えないことを確認します
    /// (U5 受け入れ条件 7)。
    func testStartFailureIsRecordedOnceAsStart() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.activity.startError = SessionActivityPortError.notAuthorized
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.start])
        XCTAssertEqual(harness.activity.startedContents.count, 1, "開始は境界へ届いている")
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [], "開始できなかった表示を開始済みとして残さない")

        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 20))
        let removalsBeforeEnd = harness.photos.removeAllCount
        await harness.send(harness.state(.idle, speed: 20))

        XCTAssertEqual(harness.diagnostics.failedOperations, [.start], "失敗は1件だけ")
        XCTAssertGreaterThan(harness.photos.removeAllCount, removalsBeforeEnd, "表示の失敗の後もセッションの終わりの後片付けは行う")
    }

    /// 責務: 更新が throw しても例外を出さず、診断へ更新として1件ずつ残し、失敗の後の更新と終了も境界へ届くことを確認します(U5 受け入れ条件 7)。
    func testUpdateFailureIsRecordedOnceAsUpdate() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.updateError = SessionActivityPortError.notPresenting
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 20))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.update])

        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 30))
        XCTAssertEqual(harness.activity.updatedContents.map(\.vehicleSpeed), [.value(20), .value(30)], "失敗の後の更新も届く")
        XCTAssertEqual(harness.diagnostics.failedOperations, [.update, .update], "失敗ごとに1件")

        await harness.send(harness.state(.idle, speed: 30))
        XCTAssertEqual(harness.activity.endedContents.count, 1, "失敗の後の終了も届く")
        XCTAssertFalse(harness.activity.isPresenting)
        XCTAssertEqual(harness.diagnostics.failedOperations, [.update, .update])
    }

    /// 責務: 終了が throw しても例外を出さず、診断へ終了として1件残し、次のセッションの表示の操作が境界へ届くことを確認します(U5 受け入れ条件 7)。
    func testEndFailureIsRecordedOnceAsEnd() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.endError = SessionActivityPortError.notPresenting
        await harness.send(harness.state(.idle, speed: 10))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.end])
        XCTAssertEqual(harness.activity.endedContents.count, 1, "終了は境界へ届いている")
        XCTAssertFalse(harness.lifecycleDiagnostics.events.contains(.ended), "終了できなかった表示を終了済みとして残さない")

        harness.activity.endError = nil
        harness.currentDate = harness.currentDate.addingTimeInterval(60)
        let nextStartedAt = harness.currentDate
        await harness.send(harness.state(.loaded, speed: 20))
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 30))

        let nextSessionCalls = harness.activity.calls.filter {
            switch $0 {
            case let .start(content), let .update(content): content.startedAt == nextStartedAt
            case .end, .endOrphanedPresentations: false
            }
        }
        XCTAssertFalse(nextSessionCalls.isEmpty, "次のセッションの表示の操作が届かない: \(harness.activity.calls)")
        XCTAssertEqual(harness.diagnostics.failedOperations, [.end], "失敗は1件だけ")
    }

    /// 責務: 開始が失敗しても、その後の記録の更新処理が続き新しい開始を妨げないことを確認します。
    func testStartFailureDoesNotBlockLaterForegroundStart() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.activity.startError = SessionActivityPortError.notAuthorized
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.startError = nil
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 2)
        XCTAssertTrue(harness.activity.isPresenting)
    }
}
