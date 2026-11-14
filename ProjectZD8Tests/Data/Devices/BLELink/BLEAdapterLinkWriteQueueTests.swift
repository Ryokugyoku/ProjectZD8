import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLinkWriteQueue` の受け付け・送信制御・完了・失敗・破棄を検証します。
@MainActor
final class BLEAdapterLinkWriteQueueTests: XCTestCase {
    /// 書き込み先のService UUIDです。
    private let service = "FFF0"
    /// 書き込み先のCharacteristic UUIDです。
    private let characteristic = "FFF2"

    /// 有効化前は受け付けず `notReady` で失敗します。
    ///
    /// 責務: 初期の `isActive` と有効化前の `enqueue` を確認します。
    func testEnqueueBeforeActivateFailsWithNotReady() async throws {
        let queue = BLEAdapterLinkWriteQueue()
        XCTAssertFalse(queue.isActive)

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1])) }
        try await BLEBoundedWaiter.waitUntil("enqueue") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .failed(.notReady))
    }

    /// 有効化すると受け付け、空データは書き込まずに成功します。
    ///
    /// 責務: `activate` 後の `isActive` と空データの扱いを確認します。
    func testActivateEnablesQueueAndEmptyDataSucceedsWithoutWriting() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withoutResponse, maximumLength: 4)
        XCTAssertTrue(queue.isActive)

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data()) }
        try await BLEBoundedWaiter.waitUntil("empty enqueue") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(peripheral.calls, [])
    }

    /// 最大書き込み長が0以下なら `writeFailed` で失敗し、何も書き込みません。
    ///
    /// 責務: 分割できない最大長の扱いを確認します。
    func testInvalidMaximumLengthFailsWithWriteFailed() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withoutResponse, maximumLength: 0)

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("enqueue") { attempt.isFinished }

        guard case .failed(.writeFailed) = attempt.outcome else {
            return XCTFail("最大長0は writeFailed になる必要があります: \(String(describing: attempt.outcome))")
        }
        XCTAssertEqual(peripheral.calls, [])
    }

    /// 応答なしで送信可能な間は全チャンクを書き込み先へ順に書いて成功します。
    ///
    /// 責務: 書き込み先・種別・チャンク順を確認します。
    func testWithoutResponseWritesAllChunksToTarget() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withoutResponse, maximumLength: 2)

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2, 3])) }
        try await BLEBoundedWaiter.waitUntil("enqueue") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(peripheral.calls, [
            .writeValue(Data([1, 2]), characteristicUUID: characteristic, serviceUUID: service, kind: .withoutResponse),
            .writeValue(Data([3]), characteristicUUID: characteristic, serviceUUID: service, kind: .withoutResponse)
        ])
    }

    /// 応答なしで送信不可なら止まり、`handleReadyToSend()` で再開します。
    ///
    /// 責務: 送信可能回数0では書かず、回数を与えて通知すると残りを書いて成功することを確認します。
    func testWithoutResponseWaitsUntilReadyToSend() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withoutResponse, maximumLength: 2)
        peripheral.withoutResponseSendCredits = 1

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2, 3, 4])) }
        try await BLEBoundedWaiter.waitUntil("first chunk") { peripheral.writtenChunks.count >= 1 }
        XCTAssertEqual(peripheral.writtenChunks, [Data([1, 2])])
        queue.handleReadyToSend()
        XCTAssertEqual(peripheral.writtenChunks.count, 1, "送信不可のままの通知では進みません")

        peripheral.withoutResponseSendCredits = 1
        queue.handleReadyToSend()
        try await BLEBoundedWaiter.waitUntil("completion") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(peripheral.writtenChunks, [Data([1, 2]), Data([3, 4])])
    }

    /// 応答ありは完了通知ごとに1チャンクずつ進み、最後の完了で成功します。
    ///
    /// 責務: 完了通知前に次を書かないことと、最終完了で呼び出しが終わることを確認します。
    func testWithResponseAdvancesOneChunkPerCompletion() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withResponse, maximumLength: 2)

        let attempt = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2, 3])) }
        try await BLEBoundedWaiter.waitUntil("first chunk") { peripheral.writtenChunks.count >= 1 }
        XCTAssertEqual(peripheral.writtenChunks, [Data([1, 2])])
        queue.handleWriteCompleted(errorDescription: nil)
        XCTAssertEqual(peripheral.writtenChunks, [Data([1, 2]), Data([3])])
        XCTAssertFalse(attempt.isFinished)
        queue.handleWriteCompleted(errorDescription: nil)
        try await BLEBoundedWaiter.waitUntil("completion") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(peripheral.writeCalls.count, 2)
    }

    /// 応答待ちでない時の完了通知は無視します。
    ///
    /// 責務: 送信待ちがない状態の完了通知で書き込みが起きないことを確認します。
    func testCompletionWithoutPendingWriteIsIgnored() {
        let (queue, peripheral) = makeActiveQueue(kind: .withResponse, maximumLength: 2)

        queue.handleWriteCompleted(errorDescription: nil)
        queue.handleWriteCompleted(errorDescription: "late")

        XCTAssertEqual(peripheral.calls, [])
        XCTAssertTrue(queue.isActive)
    }

    /// 完了通知のエラーはその呼び出しだけを `writeFailed` で終え、次の呼び出しを進めます。
    ///
    /// 責務: 失敗した呼び出しの残りチャンクを書かず、後続の呼び出しが送られて成功することを確認します。
    func testCompletionErrorFailsCurrentWriteAndContinuesWithNext() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withResponse, maximumLength: 1)
        let first = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("first chunk") { peripheral.writtenChunks.count >= 1 }
        let second = BLEWriteAttemptRecorder { try await queue.enqueue(Data([9])) }
        try await BLEBoundedWaiter.settle()

        queue.handleWriteCompleted(errorDescription: "ATT error")
        try await BLEBoundedWaiter.waitUntil("first fails") { first.isFinished }
        XCTAssertEqual(first.outcome, .failed(.writeFailed(description: "ATT error")))
        XCTAssertEqual(peripheral.writtenChunks, [Data([1]), Data([9])])
        queue.handleWriteCompleted(errorDescription: nil)
        try await BLEBoundedWaiter.waitUntil("second completes") { second.isFinished }

        XCTAssertEqual(second.outcome, .succeeded)
    }

    /// `failAll(with:)` は待機中の全呼び出しを指定エラーで終え、受け付けを止めます。
    ///
    /// 責務: 2件の待機中呼び出しが同じエラーで終わり、以後の `enqueue` が `notReady` になることを確認します。
    func testFailAllEndsAllPendingWritesAndDeactivates() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withResponse, maximumLength: 1)
        let first = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("first chunk") { peripheral.writtenChunks.count >= 1 }
        let second = BLEWriteAttemptRecorder { try await queue.enqueue(Data([3])) }
        try await BLEBoundedWaiter.settle()

        queue.failAll(with: .linkLost)
        try await BLEBoundedWaiter.waitUntil("both fail") { first.isFinished && second.isFinished }

        XCTAssertEqual(first.outcome, .failed(.linkLost))
        XCTAssertEqual(second.outcome, .failed(.linkLost))
        XCTAssertFalse(queue.isActive)
        let after = BLEWriteAttemptRecorder { try await queue.enqueue(Data([4])) }
        try await BLEBoundedWaiter.waitUntil("after failAll") { after.isFinished }
        XCTAssertEqual(after.outcome, .failed(.notReady))
        XCTAssertEqual(peripheral.writtenChunks, [Data([1])])
    }

    /// 連続した呼び出しのチャンクは呼び出し順に並び、混ざりません。
    ///
    /// 責務: 応答待ち中に追加した呼び出しが、先の呼び出しの全チャンクの後に送られることを確認します。
    func testConsecutiveEnqueuesKeepCallOrder() async throws {
        let (queue, peripheral) = makeActiveQueue(kind: .withResponse, maximumLength: 1)
        let first = BLEWriteAttemptRecorder { try await queue.enqueue(Data([1, 2])) }
        try await BLEBoundedWaiter.waitUntil("first chunk") { peripheral.writtenChunks.count >= 1 }
        let second = BLEWriteAttemptRecorder { try await queue.enqueue(Data([3, 4])) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(peripheral.writtenChunks, [Data([1])])

        for _ in 0..<4 { queue.handleWriteCompleted(errorDescription: nil) }
        try await BLEBoundedWaiter.waitUntil("both complete") { first.isFinished && second.isFinished }

        XCTAssertEqual(peripheral.writtenChunks, [Data([1]), Data([2]), Data([3]), Data([4])])
        XCTAssertEqual(first.outcome, .succeeded)
        XCTAssertEqual(second.outcome, .succeeded)
    }

    /// 指定種別・最大長で有効化したキューと書き込み先を返します。
    ///
    /// 責務: ペリフェラル役フェイクを書き込み先にしてキューを有効化します。
    /// - Parameters:
    ///   - kind: 書き込み種別。
    ///   - maximumLength: 最大書き込み長。
    /// - Returns: 有効化したキューと書き込み先。
    private func makeActiveQueue(kind: BLEWriteKind, maximumLength: Int) -> (BLEAdapterLinkWriteQueue, BLEPeripheralRoleFake) {
        let peripheral = BLEPeripheralRoleFake(identifier: BLEAdapterLinkTestHarness.targetIdentifier, connectionState: .connected)
        peripheral.maximumWriteLengths = [kind: maximumLength]
        let queue = BLEAdapterLinkWriteQueue()
        queue.activate(.init(peripheral: peripheral, serviceUUID: service, characteristicUUID: characteristic, kind: kind))
        addTeardownBlock { @MainActor in queue.failAll(with: .stopped) }
        return (queue, peripheral)
    }
}
