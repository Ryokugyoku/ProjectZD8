import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink.write(_:)` の完了待ちに期限があり、期限を超えたらタイムアウトの失敗で戻り、リンク障害として扱うことを検証します。
///
/// 仕様: U5 受け入れ条件 1・2・4(B1)。期限は注入した待機手段で発火させ、実時間を待ちません。
/// 期限の待機は「書き込みを始めた後に新しく要求され、まだ戻していない待機」として探します(探索の期限とは別の期限)。
@MainActor
final class BLEAdapterLinkWriteTimeoutTests: XCTestCase {
    /// 実物のリンクとフェイクを組み合わせた準備の型です。
    private typealias Harness = BLEAdapterLinkTestHarness
    /// BLE UART の Characteristic 能力の共通 fixture です。
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// 応答なし書き込みの最大書き込み長です。
    private let withoutResponseMTU = 8
    /// 応答あり書き込みの最大書き込み長です。
    private let withResponseMTU = 5

    /// 指定の書き込み能力で `ready` まで進めた準備を返します。
    ///
    /// 責務: 種別ごとの最大書き込み長を設定し、FFF0構成で `ready` まで進めます。
    /// - Parameter write: FFF2の能力。
    /// - Returns: `ready` のリンクの準備。
    private func makeReadyHarness(write: AppleBluetoothCharacteristicCapability) -> Harness {
        let harness = Harness()
        harness.peripheral.maximumWriteLengths = [.withoutResponse: withoutResponseMTU, .withResponse: withResponseMTU]
        harness.driveToReady(write: write)
        XCTAssertEqual(harness.link.state, .ready)
        return harness
    }

    /// 書き込みの開始後に新しく要求され、まだ戻していない待機(書き込みの期限)を上限付きで探します。
    ///
    /// 責務: 開始前の要求件数より後の位置で、キャンセルされていない待機が現れるまで待ち、その位置を返します。見つからなければ失敗させます。
    /// - Parameters:
    ///   - harness: 準備。
    ///   - requestsBefore: 書き込みを始める前の待機の要求件数。
    /// - Returns: 書き込みの期限の待機の位置。見つからなければ `nil`。
    private func waitForWriteDeadline(
        _ harness: Harness, after requestsBefore: Int, file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Int? {
        let found = try await BLEBoundedWaiter.waitUntil("書き込みの期限の待機", file: file, line: line) {
            harness.sleepController.activeIndices.contains { $0 >= requestsBefore }
        }
        guard found else { return nil }
        return harness.sleepController.activeIndices.first { $0 >= requestsBefore }
    }

    /// 結果がタイムアウトの失敗かどうかを返します。
    ///
    /// 責務: 結果が `AdapterLinkWriteError.timedOut` の失敗であることを判定します。
    /// - Parameter outcome: 書き込みの結果。
    /// - Returns: タイムアウトの失敗なら `true`。
    private func isTimedOut(_ outcome: BLEWriteAttemptRecorder.Outcome?) -> Bool {
        outcome == .failed(.timedOut)
    }

    /// 応答あり書き込みの完了通知が来なければ、期限で書き込みはタイムアウトの失敗で戻り、リンクは切断から再接続へ進みます。
    ///
    /// 責務: 1チャンク目の完了通知を流さずに期限を発火させ、結果がタイムアウトの失敗・状態が切断・再接続の要求が増えることを確認します
    /// (受け入れ条件 1・2・4。現行は期限が無く、書き込みは戻らない)。
    func testWithResponseWriteWithoutCompletionTimesOutAsLinkFailure() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let requestsBefore = harness.sleepController.requestCount
        let connectsBefore = harness.central.connectCallCount
        let attempt = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))
        try await BLEBoundedWaiter.waitUntil("1チャンク目") { harness.peripheral.writtenChunks.count == 1 }

        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }
        harness.sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("書き込みの決着") { attempt.isFinished }

        XCTAssertTrue(isTimedOut(attempt.outcome), "タイムアウトの失敗で戻る: \(String(describing: attempt.outcome))")
        guard case .disconnected = harness.link.state else {
            return XCTFail("タイムアウトはリンク障害として切断へ進む: \(harness.link.state)")
        }
        let reconnecting = harness.central.connectCallCount > connectsBefore
            || harness.central.calls.contains(.cancelConnection(Harness.targetIdentifier))
        XCTAssertTrue(reconnecting, "切断→再接続の流れへ入る: \(harness.central.calls)")
    }

    /// 応答なし書き込みが送信可能にならなければ、期限で書き込みはタイムアウトの失敗で戻ります。
    ///
    /// 責務: 送信可能回数0のまま期限を発火させ、結果がタイムアウトの失敗・状態が切断になることを確認します(受け入れ条件 1・2・4)。
    func testWithoutResponseWriteStalledUntilReadyToSendTimesOut() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithoutResponseFFF2)
        defer { harness.tearDown() }
        harness.peripheral.withoutResponseSendCredits = 0
        let requestsBefore = harness.sleepController.requestCount
        let attempt = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))

        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }
        harness.sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("書き込みの決着") { attempt.isFinished }

        XCTAssertTrue(isTimedOut(attempt.outcome), "タイムアウトの失敗で戻る: \(String(describing: attempt.outcome))")
        guard case .disconnected = harness.link.state else {
            return XCTFail("タイムアウトはリンク障害として切断へ進む: \(harness.link.state)")
        }
    }

    /// 期限で、待っている書き込みだけでなく後ろに並んだ書き込みも失敗で戻ります(遅れた完了通知が次の書き込みに当たらないため)。
    ///
    /// 責務: 1回目の応答待ちの間に2回目を並べて期限を発火させ、両方が決着し、どちらも成功しないことを確認します(受け入れ条件 2)。
    func testTimeoutFailsQueuedWritesToo() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let requestsBefore = harness.sleepController.requestCount
        let first = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))
        try await BLEBoundedWaiter.waitUntil("1回目の1チャンク目") { harness.peripheral.writtenChunks.count == 1 }
        let second = harness.beginWrite(Data([0x30, 0x31, 0x30, 0x43, 0x0D]))

        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }
        harness.sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("両方の書き込みの決着") { first.isFinished && second.isFinished }

        XCTAssertTrue(isTimedOut(first.outcome), "待っていた書き込みはタイムアウト: \(String(describing: first.outcome))")
        XCTAssertNotEqual(second.outcome, .succeeded)
        XCTAssertEqual(harness.peripheral.writtenChunks.count, 1, "期限の後に2回目のチャンクを送らない")
    }

    /// タイムアウトの切断は、他の切断と区別できる理由(`writeTimedOut`)で出し、キャンセル完了の切断通知の後に同じアダプターへ再接続します。
    ///
    /// 責務: 期限の発火で `.disconnected(.writeTimedOut)` と接続キャンセルが出て、切断通知の後に接続要求が増えることを確認します(受け入れ条件 2)。
    func testTimeoutDisconnectsWithDistinctReasonAndReconnects() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let requestsBefore = harness.sleepController.requestCount
        let attempt = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))
        try await BLEBoundedWaiter.waitUntil("1チャンク目") { harness.peripheral.writtenChunks.count == 1 }
        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }

        harness.sleepController.fire(deadline)
        try await BLEBoundedWaiter.waitUntil("書き込みの決着") { attempt.isFinished }

        XCTAssertEqual(harness.link.state, .disconnected(.writeTimedOut))
        XCTAssertEqual(harness.central.calls.last, .cancelConnection(Harness.targetIdentifier))
        let connects = harness.central.connectCallCount
        harness.peripheral.connectionState = .disconnected
        harness.central.emit(.didDisconnect(harness.peripheral, errorDescription: nil))
        try await BLEBoundedWaiter.waitUntil("再接続の要求") { harness.central.connectCallCount == connects + 1 }
    }

    /// 期限の前に完了すれば成功し、その後に古い期限の待機が戻っても切断しません。
    ///
    /// 責務: 完了通知で成功した後、書き込みの期限の待機を発火させても `ready` のままで、次の書き込みも成功することを確認します(受け入れ条件 3)。
    func testCompletionBeforeDeadlineSucceedsAndStaleDeadlineDoesNotFire() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let requestsBefore = harness.sleepController.requestCount
        let attempt = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))
        try await BLEBoundedWaiter.waitUntil("1チャンク目") { harness.peripheral.writtenChunks.count == 1 }
        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }

        harness.peripheral.emit(.didWriteValue(characteristicUUID: Fixtures.fff2Write, errorDescription: nil))
        try await BLEBoundedWaiter.waitUntil("書き込みの決着") { attempt.isFinished }
        XCTAssertEqual(attempt.outcome, .succeeded)
        harness.sleepController.fire(deadline)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.link.state, .ready, "完了した書き込みの古い期限で切断しない")
        let next = harness.beginWrite(Data([0x30, 0x0D]))
        try await BLEBoundedWaiter.waitUntil("2回目の1チャンク目") { harness.peripheral.writtenChunks.count == 2 }
        harness.peripheral.emit(.didWriteValue(characteristicUUID: Fixtures.fff2Write, errorDescription: nil))
        try await BLEBoundedWaiter.waitUntil("2回目の決着") { next.isFinished }
        XCTAssertEqual(next.outcome, .succeeded)
    }

    /// 書き込みの期限の待ち時間は、上限値の書き込み完了待ち(既定10秒)です。
    ///
    /// 責務: ハーネスの上限値(書き込み期限は既定)で、書き込み開始後に要求された待機が10秒であることを確認します(受け入れ条件 1)。
    func testDeadlineUsesWriteCompletionTimeout() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let requestsBefore = harness.sleepController.requestCount
        _ = harness.beginWrite(Data([0x41, 0x0D]))
        guard let deadline = try await waitForWriteDeadline(harness, after: requestsBefore) else { return }
        XCTAssertEqual(harness.sleepController.requestedDurations[deadline], .seconds(10))
    }
}
