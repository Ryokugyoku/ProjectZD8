import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` が、表示の開始・更新のたびに、受け付けた時刻の60秒後を有効期限として境界へ渡すことのテストです。
///
/// 仕様: S2-1。間引きで送らなかった更新には有効期限も渡りません。時刻は注入した `now()` を基準にします。
@MainActor
final class RecordingSessionActivityUseCaseStaleDateTests: XCTestCase {
    /// 責務: 前面で始まった表示の有効期限が、開始を受け付けた時刻の60秒後であることを確認します。
    func testStartPassesStaleDateSixtySecondsAfterNow() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.currentDate = Date(timeIntervalSince1970: 5_000)

        await harness.send(harness.state(.loaded, speed: 10))

        XCTAssertEqual(harness.activity.startedStaleDates, [Date(timeIntervalSince1970: 5_060)])
    }

    /// 責務: 3秒後に送った更新の有効期限が、開始の期限ではなく更新を受け付けた時刻の60秒後であることを確認します。
    func testUpdatePassesStaleDateFromUpdateTime() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.currentDate = Date(timeIntervalSince1970: 1_000)
        await harness.send(harness.state(.loaded, speed: 10))

        harness.currentDate = Date(timeIntervalSince1970: 1_003)
        await harness.send(harness.state(.loaded, speed: 20))

        XCTAssertEqual(harness.activity.startedStaleDates, [Date(timeIntervalSince1970: 1_060)])
        XCTAssertEqual(harness.activity.updatedStaleDates, [Date(timeIntervalSince1970: 1_063)])
    }

    /// 責務: 時刻を進めて更新を重ねると、そのたびに新しい時刻の60秒後が渡ることを確認します。
    func testEachUpdateGetsFreshStaleDate() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.currentDate = Date(timeIntervalSince1970: 1_000)
        await harness.send(harness.state(.loaded, speed: 10))

        harness.currentDate = Date(timeIntervalSince1970: 1_010)
        await harness.send(harness.state(.loaded, speed: 20))
        harness.currentDate = Date(timeIntervalSince1970: 1_100)
        await harness.send(harness.state(.loaded, speed: 30))

        XCTAssertEqual(
            harness.activity.updatedStaleDates,
            [Date(timeIntervalSince1970: 1_070), Date(timeIntervalSince1970: 1_160)]
        )
    }

    /// 責務: 間引きで送らなかった更新には有効期限も渡らず、送った更新の件数と期限の件数が一致することを確認します。
    func testThrottledUpdateDoesNotPassStaleDate() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.currentDate = Date(timeIntervalSince1970: 1_000)
        await harness.send(harness.state(.loaded, speed: 10))

        harness.currentDate = Date(timeIntervalSince1970: 1_002)
        await harness.send(harness.state(.loaded, speed: 20))
        XCTAssertEqual(harness.activity.updatedStaleDates, [], "間引いた更新に期限は渡らない")

        harness.currentDate = Date(timeIntervalSince1970: 1_004)
        await harness.send(harness.state(.loaded, speed: 30))

        XCTAssertEqual(harness.activity.updatedContents.count, 1)
        XCTAssertEqual(harness.activity.updatedStaleDates, [Date(timeIntervalSince1970: 1_064)])
    }

    /// 責務: 背面で始まった記録を前面復帰で表示する時、期限は記録開始の時刻ではなく前面復帰で開始を受け付けた時刻の60秒後であることを確認します。
    func testForegroundStartUsesForegroundTime() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.foreground = false
        harness.currentDate = Date(timeIntervalSince1970: 1_000)
        await harness.send(harness.state(.loaded, speed: 10))

        harness.foreground = true
        harness.currentDate = Date(timeIntervalSince1970: 1_500)
        await harness.enterForeground()

        XCTAssertEqual(harness.activity.startedStaleDates, [Date(timeIntervalSince1970: 1_560)])
    }

    /// 責務: システムに閉じられた後の再開でも、再開を受け付けた時刻の60秒後が渡ることを確認します。
    func testRestartAfterSystemDismissalUsesRestartTime() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.currentDate = Date(timeIntervalSince1970: 1_000)
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.simulateSystemDismissal()

        harness.currentDate = Date(timeIntervalSince1970: 2_000)
        await harness.enterForeground()

        XCTAssertEqual(
            harness.activity.startedStaleDates,
            [Date(timeIntervalSince1970: 1_060), Date(timeIntervalSince1970: 2_060)]
        )
    }
}
