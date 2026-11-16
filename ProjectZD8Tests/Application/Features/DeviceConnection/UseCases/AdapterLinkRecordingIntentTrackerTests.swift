import Foundation
import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingIntentTracker` の意思の保持・有効期限・1回で消えること・捨てた時の理由つき通知を、fake の時計で検証します。
///
/// 仕様: U4 受け入れ条件 5〜7・10。有効期限は選択から2分(ちょうど2分は有効)。
@MainActor
final class AdapterLinkRecordingIntentTrackerTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 監視の時計の fake です。
    private var clock: AdapterLinkSupervisionClockFake!
    /// 通知の spy です。
    private var notifications: VehicleDetectionNotificationSpy!

    /// 責務: テストごとに時計と通知を作り直します。
    override func setUp() async throws {
        try await super.setUp()
        clock = AdapterLinkSupervisionClockFake(now: F.referenceDate)
        notifications = VehicleDetectionNotificationSpy()
    }

    /// 責務: 保留中の待機を終わらせます。
    override func tearDown() async throws {
        clock?.sleeps.failAllPending()
        clock = nil
        notifications = nil
        try await super.tearDown()
    }

    /// 検証対象を作ります。
    ///
    /// 責務: fake の時計と通知の spy を注入した型を返します。
    /// - Returns: 検証対象。
    private func makeTracker() -> AdapterLinkRecordingIntentTracker {
        AdapterLinkRecordingIntentTracker(clock: clock, notifications: notifications)
    }

    /// 意思を保持し、期限の満了の待ちが始まるまで待ちます。
    ///
    /// 責務: `keep()` を呼び、待機が1件増えるまで上限付きで待ちます。
    /// - Parameter tracker: 検証対象。
    private func keepAndWaitForExpirySleep(_ tracker: AdapterLinkRecordingIntentTracker, file: StaticString = #filePath, line: UInt = #line) async throws {
        let sleeps = clock.requestedDurations.count
        tracker.keep()
        try await BLEBoundedWaiter.waitUntil("期限の待ち", file: file, line: line) { clock.requestedDurations.count == sleeps + 1 }
    }

    /// 保持の前は意思が無く、有効でもありません。
    ///
    /// 責務: 生成直後の `intent` が `nil`、`hasValidIntent` が偽であることを確認します。
    func testInitiallyHasNoIntent() {
        let tracker = makeTracker()
        XCTAssertNil(tracker.intent)
        XCTAssertFalse(tracker.hasValidIntent)
    }

    /// 保持すると、現在時刻を起点にした意思になり、期限(2分)を1ミリ秒超えた時点の満了の待ちが始まります。
    ///
    /// 責務: `selectedAt` が時計の現在時刻で、待機が 120.001 秒で1件要求されることを確認します(受け入れ条件 5)。
    func testKeepStoresNowAndWaitsForExpiry() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        XCTAssertEqual(tracker.intent, AdapterLinkRecordingIntent(selectedAt: F.referenceDate))
        XCTAssertEqual(clock.requestedDurations, [.milliseconds(120_001)])
        XCTAssertTrue(tracker.hasValidIntent)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])
    }

    /// 意思は期限の直前・ちょうど2分まで有効で、直後は無効です。
    ///
    /// 責務: 時計を 119.999・120・120.001 秒へ進めた時の `hasValidIntent` を確認します(受け入れ条件 10 の境界)。
    func testHasValidIntentBoundaries() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        clock.now = F.date(119.999)
        XCTAssertTrue(tracker.hasValidIntent, "直前")
        clock.now = F.date(120)
        XCTAssertTrue(tracker.hasValidIntent, "ちょうど")
        clock.now = F.date(120.001)
        XCTAssertFalse(tracker.hasValidIntent, "直後")
    }

    /// 期限内の検知の完了で意思は使われて消え、失敗の通知は出ません。2回目の検知では使えません。
    ///
    /// 責務: ちょうど2分の検知完了で `intent` が `nil` になり、通知0件、その後の `hasValidIntent` が偽であることを確認します(受け入れ条件 6)。
    func testDetectionWithinLifetimeConsumesIntentOnce() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        clock.now = F.date(120)

        tracker.detectionDidComplete()

        XCTAssertNil(tracker.intent)
        XCTAssertFalse(tracker.hasValidIntent)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])
        tracker.detectionDidComplete()
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [], "2回目の検知では何もしない")
    }

    /// 期限を過ぎてからの検知の完了では、意思を捨てて「車両を検知できなかった」を1回知らせます。
    ///
    /// 責務: 120.001 秒の検知完了で `intent` が `nil`、理由が `.vehicleNotDetected` の1件であることを確認します(受け入れ条件 7)。
    func testDetectionAfterExpiryDiscardsWithVehicleNotDetected() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        clock.now = F.date(120.001)

        tracker.detectionDidComplete()

        XCTAssertNil(tracker.intent)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [.vehicleNotDetected])
    }

    /// 意思が無い時の検知の完了は何もしません。
    ///
    /// 責務: 通知0件・`intent` が `nil` のままであることを確認します。
    func testDetectionWithoutIntentDoesNothing() {
        let tracker = makeTracker()
        tracker.detectionDidComplete()
        XCTAssertNil(tracker.intent)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])
    }

    /// 期限の待ちが明け、期限を過ぎていれば、意思を捨てて「車両を検知できなかった」を知らせます。
    ///
    /// 責務: 時計を 120.001 秒進めて待ちを終えると、`intent` が `nil` で理由が1件になることを確認します(受け入れ条件 7 の期限切れ時の通知)。
    func testExpirySleepAfterLifetimeNotifiesVehicleNotDetected() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)

        clock.finishOldestSleep(advancingBy: 120.001)

        try await BLEBoundedWaiter.waitUntil("期限切れの通知") { !notifications.presentedRecordingStartFailedReasons.isEmpty }
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [.vehicleNotDetected])
        XCTAssertNil(tracker.intent)
    }

    /// 期限の待ちが明けても時計が期限内なら、意思を保持したまま何も知らせません。
    ///
    /// 責務: 時計を進めずに待ちを終えた時、通知0件で意思が有効なままであることを確認します。
    func testExpirySleepWithinLifetimeKeepsIntent() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)

        clock.finishOldestSleep(advancingBy: 120)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])
        XCTAssertTrue(tracker.hasValidIntent)
    }

    /// 意思を使った後に古い期限の待ちが明けても、通知を出しません。
    ///
    /// 責務: 検知完了で消した後、期限を過ぎて待ちが明けても通知0件であることを確認します。
    func testExpirySleepAfterConsumptionDoesNotNotify() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        tracker.detectionDidComplete()

        clock.finishOldestSleep(advancingBy: 200)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])
    }

    /// 2回目の選択は意思を置き換え、期限の起点を新しい選択の時刻に取り直します。
    ///
    /// 責務: 60秒後の2回目の保持で `selectedAt` が60秒後になり、最初の選択から 120.001 秒後でも有効なことを確認します。
    func testKeepAgainRestartsLifetime() async throws {
        let tracker = makeTracker()
        try await keepAndWaitForExpirySleep(tracker)
        clock.now = F.date(60)
        try await keepAndWaitForExpirySleep(tracker)

        XCTAssertEqual(tracker.intent, AdapterLinkRecordingIntent(selectedAt: F.date(60)))
        clock.now = F.date(120.001)
        XCTAssertTrue(tracker.hasValidIntent)
        clock.now = F.date(180.001)
        XCTAssertFalse(tracker.hasValidIntent)
    }

    /// 処理できなくなった時に意思を捨てると、理由を1回知らせます。意思が無ければ何もしません。
    ///
    /// 責務: 意思ありの `discard(.signInRequired)` で通知1件・`intent` が `nil`、続く `discard` で通知が増えないことを確認します(受け入れ条件 7)。
    func testDiscardNotifiesReasonOnlyWhenIntentExists() async throws {
        let tracker = makeTracker()
        tracker.discard(.adapterNotConfigured)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [])

        try await keepAndWaitForExpirySleep(tracker)
        tracker.discard(.signInRequired)
        tracker.discard(.adapterNotConfigured)

        XCTAssertNil(tracker.intent)
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, [.signInRequired])
    }

    /// 選択そのものを処理できない時は、意思を保持せずに理由を知らせます。
    ///
    /// 責務: 理由ごとに通知が1件ずつ出て、`intent` が `nil` で待機も始まらないことを確認します(受け入れ条件 7)。
    func testRejectSelectionNotifiesWithoutKeeping() {
        let tracker = makeTracker()
        for reason in AdapterLinkRecordingStartFailureReason.allCases {
            tracker.rejectSelection(reason)
        }
        XCTAssertEqual(notifications.presentedRecordingStartFailedReasons, AdapterLinkRecordingStartFailureReason.allCases)
        XCTAssertNil(tracker.intent)
        XCTAssertEqual(clock.requestedDurations, [])
    }
}
