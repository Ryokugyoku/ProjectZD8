import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLinkWriteQueue` の「送信待ちが進まない時間」の期限を、手動で発火させる待機で検証します。
///
/// 仕様: U5 受け入れ条件 1〜3(B1)。期限の直前の完了は成功、期限ちょうど(待機が戻った時)で全件タイムアウト、完了後に期限が誤発火しない、
/// 進まないまま後ろに並んだ書き込みでは期限を延ばさない。
@MainActor
final class BLEAdapterLinkWriteQueueTimeoutTests: XCTestCase {
    /// 書き込み先のService UUIDです。
    private let service = "FFF0"
    /// 書き込み先のCharacteristic UUIDです。
    private let characteristic = "FFF2"
    /// テストが注入する期限です。
    private let timeout: Duration = .seconds(3)
    /// 待機手段です。
    private var sleepController: BLEManualSleepController!

    /// 期限切れの通知回数を数える入れ物です。
    @MainActor
    private final class TimeoutCounter {
        /// 通知回数です。
        var count = 0
    }

    /// 責務: テストごとに待機手段を作り直します。
    override func setUp() async throws {
        try await super.setUp()
        sleepController = BLEManualSleepController()
    }

    /// 責務: 残った待機を終わらせます。
    override func tearDown() async throws {
        sleepController?.drain()
        sleepController = nil
        try await super.tearDown()
    }

    /// 期限と待機手段を注入して有効化したキューと、期限切れの通知回数の記録を返します。
    ///
    /// 責務: 指定の書き込み種別・最大長でキューを有効化し、`writeDidTimeOut` を数えます。
    /// - Parameters:
    ///   - kind: 書き込み種別。
    ///   - maximumLength: 最大書き込み長。
    /// - Returns: キュー・ペリフェラル・期限切れの通知回数を読む処理。
    private func makeQueue(
        kind: BLEWriteKind, maximumLength: Int = 4
    ) -> (BLEAdapterLinkWriteQueue, BLEPeripheralRoleFake, @MainActor () -> Int) {
        let peripheral = BLEPeripheralRoleFake(identifier: BLEAdapterLinkTestHarness.targetIdentifier, connectionState: .connected)
        peripheral.maximumWriteLengths = [kind: maximumLength]
        let queue = BLEAdapterLinkWriteQueue(completionTimeout: timeout, sleep: sleepController.sleep)
        let counter = TimeoutCounter()
        queue.writeDidTimeOut = { counter.count += 1 }
        queue.activate(.init(peripheral: peripheral, serviceUUID: service, characteristicUUID: characteristic, kind: kind))
        addTeardownBlock { @MainActor in queue.failAll(with: .stopped) }
        return (queue, peripheral, { counter.count })
    }

    /// まだ戻していない、キャンセルされていない待機の位置を上限付きで待って返します。
    ///
    /// 責務: 有効な期限の待機がちょうど指定件数になるまで待ち、最後の位置を返します。
    /// - Parameter count: 待つ有効な待機の件数。
    /// - Returns: 最後の有効な待機の位置。見つからなければ `nil`。
    private func waitForActiveDeadline(count: Int = 1, file: StaticString = #filePath, line: UInt = #line) async throws -> Int? {
        let found = try await BLEBoundedWaiter.waitUntil("有効な期限 \(count) 件", file: file, line: line) {
            sleepController.activeIndices.count == count
        }
        return found ? sleepController.activeIndices.last : nil
    }

    /// チャンクを送ると、注入した長さの期限を1件だけ設定します。
    ///
    /// 責務: 応答ありの1チャンク目の送信で、要求された待機が注入した期限の1件であることを確認します(受け入れ条件 1)。
    func testSendingChunkArmsInjectedTimeout() async throws {
        let (queue, _, _) = makeQueue(kind: .withResponse)
        _ = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        _ = try await waitForActiveDeadline()
        XCTAssertEqual(sleepController.requestedDurations, [timeout])
    }

    /// 期限ちょうど(待機が戻った時)に進んでいなければ、全ての送信待ちをタイムアウトで終え、期限切れを1回通知し、受け付けを止めます。
    ///
    /// 責務: 応答待ちの1件目と後ろの2件目が `.timedOut`、通知1回、`isActive` が偽になることを確認します(受け入れ条件 2)。
    func testDeadlineFailsAllJobsWithTimedOut() async throws {
        let (queue, peripheral, timeouts) = makeQueue(kind: .withResponse)
        let first = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("1件目の送信") { peripheral.writtenChunks.count == 1 }
        let second = BLEWriteAttemptRecorder { try await queue.enqueue(Data([3])) }
        guard let deadline = try await waitForActiveDeadline() else { return }

        sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("両方の決着") { first.isFinished && second.isFinished }

        XCTAssertEqual(first.outcome, .failed(.timedOut))
        XCTAssertEqual(second.outcome, .failed(.timedOut))
        XCTAssertEqual(timeouts(), 1)
        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(peripheral.writtenChunks.count, 1)
    }

    /// 期限の直前(待機が戻る前)に完了すれば成功し、送信待ちが無くなった時点で期限を取り消し、古い待機が戻っても何も起きません。
    ///
    /// 責務: 完了で成功・有効な期限0件、古い待機の発火の後も通知0回・受け付け中のままであることを確認します(受け入れ条件 3)。
    func testCompletionBeforeDeadlineCancelsIt() async throws {
        let (queue, peripheral, timeouts) = makeQueue(kind: .withResponse)
        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("送信") { peripheral.writtenChunks.count == 1 }
        guard let deadline = try await waitForActiveDeadline() else { return }

        queue.handleWriteCompleted(errorDescription: nil)
        try await BLEBoundedWaiter.waitUntil("決着") { attempt.isFinished }
        XCTAssertEqual(attempt.outcome, .succeeded)
        _ = try await waitForActiveDeadline(count: 0)
        sleepController.fire(deadline)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(timeouts(), 0)
        XCTAssertTrue(queue.isActive)
    }

    /// 進まないまま後ろに書き込みが並んでも、期限を延ばしません(待機を要求し直しません)。
    ///
    /// 責務: 応答待ちの間に2件並べても要求された待機が1件のままで、最初の期限で両方がタイムアウトすることを確認します(受け入れ条件 2・3)。
    func testQueuedWriteWithoutProgressDoesNotExtendDeadline() async throws {
        let (queue, peripheral, _) = makeQueue(kind: .withResponse)
        let first = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1])) }
        try await BLEBoundedWaiter.waitUntil("1件目の送信") { peripheral.writtenChunks.count == 1 }
        guard let deadline = try await waitForActiveDeadline() else { return }

        let second = BLEWriteAttemptRecorder { try await queue.enqueue(Data([2])) }
        let third = BLEWriteAttemptRecorder { try await queue.enqueue(Data([3])) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(sleepController.requestCount, 1, "並んだだけでは期限を設定し直さない")

        sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("全件の決着") { first.isFinished && second.isFinished && third.isFinished }
        XCTAssertEqual([first.outcome, second.outcome, third.outcome], Array(repeating: .failed(.timedOut), count: 3))
    }

    /// 完了通知で進むたびに期限を設定し直し、前の期限の待機が戻ってもタイムアウトにしません(世代管理)。
    ///
    /// 責務: 2チャンクの1チャンク目の完了で新しい期限が要求され、古い期限の発火では決着せず、新しい期限の発火でタイムアウトすることを確認します(受け入れ条件 3)。
    func testProgressRearmsDeadlineAndOldDeadlineIsIgnored() async throws {
        let (queue, peripheral, timeouts) = makeQueue(kind: .withResponse, maximumLength: 2)
        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2, 3, 4])) }
        try await BLEBoundedWaiter.waitUntil("1チャンク目") { peripheral.writtenChunks.count == 1 }
        guard let oldDeadline = try await waitForActiveDeadline() else { return }

        queue.handleWriteCompleted(errorDescription: nil)
        try await BLEBoundedWaiter.waitUntil("新しい期限の要求") { sleepController.requestCount == 2 }
        XCTAssertEqual(peripheral.writtenChunks.count, 2)
        sleepController.fire(oldDeadline)
        try await BLEBoundedWaiter.settle()
        XCTAssertFalse(attempt.isFinished, "古い期限では決着しない")
        XCTAssertEqual(timeouts(), 0)

        guard let newDeadline = try await waitForActiveDeadline() else { return }
        sleepController.fire(newDeadline)
        try await BLEBoundedWaiter.waitUntil("決着") { attempt.isFinished }
        XCTAssertEqual(attempt.outcome, .failed(.timedOut))
        XCTAssertEqual(timeouts(), 1)
    }

    /// 応答なし書き込みで送信可能にならなければ、チャンクを送らないまま期限でタイムアウトします。
    ///
    /// 責務: 送信可能回数0で送信0件のまま期限が要求され、発火で `.timedOut` になることを確認します(受け入れ条件 1・2)。
    func testWithoutResponseStallTimesOut() async throws {
        let (queue, peripheral, timeouts) = makeQueue(kind: .withoutResponse)
        peripheral.withoutResponseSendCredits = 0
        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1])) }
        guard let deadline = try await waitForActiveDeadline() else { return }
        XCTAssertEqual(peripheral.writtenChunks, [])

        sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("決着") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .failed(.timedOut))
        XCTAssertEqual(timeouts(), 1)
    }

    /// 切断などで全件を失敗させたら期限も取り消し、その後に古い待機が戻ってもタイムアウトを通知しません。
    ///
    /// 責務: `failAll(with: .linkLost)` の結果が `.linkLost`、有効な期限0件、古い待機の発火の後も通知0回であることを確認します(受け入れ条件 3)。
    func testFailAllCancelsDeadline() async throws {
        let (queue, peripheral, timeouts) = makeQueue(kind: .withResponse)
        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1])) }
        try await BLEBoundedWaiter.waitUntil("送信") { peripheral.writtenChunks.count == 1 }
        guard let deadline = try await waitForActiveDeadline() else { return }

        queue.failAll(with: .linkLost)
        try await BLEBoundedWaiter.waitUntil("決着") { attempt.isFinished }
        _ = try await waitForActiveDeadline(count: 0)
        sleepController.fire(deadline)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(attempt.outcome, .failed(.linkLost))
        XCTAssertEqual(timeouts(), 0)
    }
}
