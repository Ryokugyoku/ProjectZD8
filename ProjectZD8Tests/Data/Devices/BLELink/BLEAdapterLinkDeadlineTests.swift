import XCTest
@testable import ProjectZD8

/// `BLEAdapterLinkDeadline` の期限設定・期限切れ・キャンセル・再設定を検証します。
@MainActor
final class BLEAdapterLinkDeadlineTests: XCTestCase {
    /// 生成直後は期限が設定されていません。
    ///
    /// 責務: 初期の `isArmed` を確認します。
    func testInitiallyNotArmed() {
        let controller = BLEManualSleepController()
        defer { controller.drain() }
        XCTAssertFalse(BLEAdapterLinkDeadline(sleep: controller.sleep).isArmed)
    }

    /// 設定した期限が戻ると1回だけ期限切れを通知し、未設定へ戻ります。
    ///
    /// 責務: 指定時間での待機要求、期限切れ通知、通知後の `isArmed` を確認します。
    func testArmedDeadlineExpiresOnceWhenSleepReturns() async throws {
        let controller = BLEManualSleepController()
        defer { controller.drain() }
        let deadline = BLEAdapterLinkDeadline(sleep: controller.sleep)
        var expirations = 0

        deadline.arm(after: .seconds(3)) { expirations += 1 }
        XCTAssertTrue(deadline.isArmed)
        try await BLEBoundedWaiter.waitUntil("sleep requested") { controller.requestCount == 1 }
        XCTAssertEqual(controller.requestedDurations, [.seconds(3)])
        controller.fire(0)
        try await BLEBoundedWaiter.waitUntil("expired") { expirations == 1 }

        XCTAssertFalse(deadline.isArmed)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(expirations, 1)
    }

    /// キャンセルした期限は戻っても通知しません。
    ///
    /// 責務: `cancel()` 後の `isArmed` と、古い待機の発火で通知されないことを確認します。
    func testCancelledDeadlineDoesNotExpire() async throws {
        let controller = BLEManualSleepController()
        defer { controller.drain() }
        let deadline = BLEAdapterLinkDeadline(sleep: controller.sleep)
        var expirations = 0
        deadline.arm(after: .seconds(1)) { expirations += 1 }
        try await BLEBoundedWaiter.waitUntil("sleep requested") { controller.requestCount == 1 }

        deadline.cancel()
        XCTAssertFalse(deadline.isArmed)
        controller.fire(0)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(expirations, 0)
    }

    /// 再設定すると古い期限は無視され、新しい期限だけが通知します。
    ///
    /// 責務: 1回目の待機を発火させても通知されず、2回目の発火で新しい処理だけが呼ばれることを確認します。
    func testRearmIgnoresPreviousDeadline() async throws {
        let controller = BLEManualSleepController()
        defer { controller.drain() }
        let deadline = BLEAdapterLinkDeadline(sleep: controller.sleep)
        var fired: [String] = []
        deadline.arm(after: .seconds(1)) { fired.append("first") }
        try await BLEBoundedWaiter.waitUntil("first sleep") { controller.requestCount == 1 }

        deadline.arm(after: .seconds(2)) { fired.append("second") }
        try await BLEBoundedWaiter.waitUntil("second sleep") { controller.requestCount == 2 }
        controller.fire(0)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(fired, [])
        XCTAssertTrue(deadline.isArmed)

        controller.fire(1)
        try await BLEBoundedWaiter.waitUntil("second expires") { fired == ["second"] }
        XCTAssertFalse(deadline.isArmed)
    }

    /// 待機がエラーで戻った場合は通知しません。
    ///
    /// 責務: 待機処理がthrowした時に期限切れとして扱わないことを確認します。
    func testThrowingSleepDoesNotExpire() async throws {
        let controller = BLEManualSleepController()
        let deadline = BLEAdapterLinkDeadline(sleep: controller.sleep)
        var expirations = 0
        deadline.arm(after: .seconds(1)) { expirations += 1 }
        try await BLEBoundedWaiter.waitUntil("sleep requested") { controller.requestCount == 1 }

        controller.drain()
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(expirations, 0)
    }
}
