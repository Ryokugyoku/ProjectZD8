import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` が、表示の開始・終了に成功したときだけ状態遷移を1回記録し、内容の更新では記録しないことのテストです。
@MainActor
final class RecordingSessionActivityUseCaseLifecycleDiagnosticsTests: XCTestCase {
    /// 責務: 表示の開始に成功すると started が1回だけ記録されることを確認します。
    func testSuccessfulStartIsRecordedOnce() async {
        let harness = RecordingSessionActivityUseCaseHarness()

        await harness.send(harness.state(.loaded, speed: 10))

        XCTAssertTrue(harness.activity.isPresenting)
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [.started])
    }

    /// 責務: 表示の開始に失敗すると何も記録されないことを確認します。
    func testFailedStartIsNotRecorded() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.activity.startError = SessionActivityPortError.notAuthorized

        await harness.send(harness.state(.loaded, speed: 10))

        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [])
    }

    /// 責務: アプリが表示を終了すると ended が1回だけ記録されることを確認します。
    func testSuccessfulEndIsRecordedOnce() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))

        await harness.send(harness.state(.idle, speed: 10))

        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [.started, .ended])
    }

    /// 責務: 表示の終了に失敗すると ended が記録されないことを確認します。
    func testFailedEndIsNotRecorded() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.endError = SessionActivityPortError.notPresenting

        await harness.send(harness.state(.idle, speed: 10))

        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [.started])
    }

    /// 責務: 内容の更新(成功)では何も記録されないことを確認します。
    func testContentUpdateIsNotRecorded() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.currentDate = harness.currentDate.addingTimeInterval(5)

        await harness.send(harness.state(.loaded, speed: 20))

        XCTAssertEqual(harness.activity.updatedContents.count, 1)
        XCTAssertEqual(harness.lifecycleDiagnostics.events, [.started])
    }
}
