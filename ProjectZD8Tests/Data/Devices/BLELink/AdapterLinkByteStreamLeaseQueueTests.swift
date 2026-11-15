import XCTest
@testable import ProjectZD8

/// `AdapterLinkByteStreamLeaseQueue` の排他・到着順・待機上限を検証します。
@MainActor
final class AdapterLinkByteStreamLeaseQueueTests: XCTestCase {
    /// 占有権を得た順の記録です。
    private final class GrantOrder {
        /// 占有権を得た利用者の名前です(得た順)。
        var names: [String] = []
    }

    /// 長い待機上限です(縮めた実時間で約2秒)。待機者が上限前に解放を受け取る検証に使います。
    private static let longTimeout: Duration = .seconds(400)

    /// 縮めた実時間で待つ待ち行列を作ります。
    ///
    /// 責務: 指定上限を200分の1の実時間で待つ待ち行列を返します。
    /// - Parameter timeout: 占有権を待つ上限。
    /// - Returns: テスト対象の待ち行列。
    private func makeQueue(timeout: Duration) -> AdapterLinkByteStreamLeaseQueue {
        AdapterLinkByteStreamLeaseQueue(timeout: timeout) { duration in
            try await Task.sleep(for: duration / AdapterLinkByteStreamHarness.defaultTimeScale)
        }
    }

    /// 占有中に要求した利用者は、解放されるまで占有権を得ません。
    ///
    /// 責務: 2人目が解放前は待ち続け、解放後に占有者になることを確認します。
    func testSecondRequesterWaitsUntilRelease() async throws {
        let queue = makeQueue(timeout: Self.longTimeout)
        let first = try await AdapterLinkBoundedAwait.value("acquire") { try await queue.acquire() }
        let waiting = Task { @MainActor in try await queue.acquire() }
        try await BLEBoundedWaiter.settle(polls: 10)
        XCTAssertEqual(queue.holder, first, "解放前に占有者が替わってはいけない")

        queue.release(first)
        let second = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: waiting, "2人目の占有"))
        XCTAssertNotNil(second)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(queue.holder, second)
    }

    /// 待っている利用者は到着順に占有権を得ます。
    ///
    /// 責務: 先に待った利用者が先に、後に待った利用者がその解放後に占有者になることを確認します。
    func testWaitersAreGrantedInArrivalOrder() async throws {
        let queue = makeQueue(timeout: Self.longTimeout)
        let grantOrder = GrantOrder()
        let first = try await AdapterLinkBoundedAwait.value("acquire") { try await queue.acquire() }
        let early = Task { @MainActor in
            let lease = try await queue.acquire()
            grantOrder.names.append("early")
            return lease
        }
        try await BLEBoundedWaiter.settle(polls: 5)
        let late = Task { @MainActor in
            let lease = try await queue.acquire()
            grantOrder.names.append("late")
            return lease
        }
        try await BLEBoundedWaiter.settle(polls: 5)

        queue.release(first)
        guard let earlyLease = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: early, "先着")) else { return }
        try await BLEBoundedWaiter.settle(polls: 5)
        XCTAssertEqual(grantOrder.names, ["early"], "先着の解放前に後着が占有してはいけない")

        queue.release(earlyLease)
        _ = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: late, "後着"))
        XCTAssertEqual(grantOrder.names, ["early", "late"])
    }

    /// 上限時間を過ぎても解放されなければ、待っている利用者は失敗します。
    ///
    /// 責務: 占有が続くと `.leaseUnavailable` で終わり、元の占有者はそのままであることを確認します。
    func testWaiterFailsAfterTimeout() async throws {
        let queue = makeQueue(timeout: .seconds(15))
        let first = try await AdapterLinkBoundedAwait.value("acquire") { try await queue.acquire() }
        let outcome = await AdapterLinkBoundedAwait.run("占有権の待機上限") { try await queue.acquire() }
        AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.leaseUnavailable)
        XCTAssertEqual(queue.holder, first)
    }

    /// 現在の占有者でない占有権の解放は何もしません。
    ///
    /// 責務: 古い占有権の解放で現在の占有者が外れないことを確認します。
    func testReleasingStaleLeaseKeepsCurrentHolder() async throws {
        let queue = makeQueue(timeout: Self.longTimeout)
        let first = try await AdapterLinkBoundedAwait.value("acquire") { try await queue.acquire() }
        queue.release(first)
        let second = try await AdapterLinkBoundedAwait.value("acquire") { try await queue.acquire() }
        queue.release(first)
        XCTAssertEqual(queue.holder, second)
    }
}
