import XCTest
@testable import ProjectZD8

/// `AdapterLinkByteStream` の受信の結合・分離・漏れ防止と、読取が必ず終わることを検証します。
@MainActor
final class AdapterLinkByteStreamTests: XCTestCase {
    /// 分割して届いたバイトは `>` まで結合して1件の応答になります。
    ///
    /// 責務: 3回に分けた受信を1回の読取が `>` を含めて返すことを確認します。
    func testReadUntilPromptJoinsChunksThroughPrompt() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        let task = Task { @MainActor in
            try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(600))
        }
        try await BLEBoundedWaiter.settle(polls: 5)
        harness.link.deliver("41 0")
        harness.link.deliver("0 BE 3E")
        harness.link.deliver(" B8 13\r>")
        let data = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: task, "分割受信の読取"))
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "41 00 BE 3E B8 13\r>")
    }

    /// 1回の受信に2件の応答が入っていても、読取ごとに1件ずつ返します。
    ///
    /// 責務: 応答境界 `>` で分け、2件目を次の読取へ残すことを確認します。
    func testConsecutiveResponsesAreNotMixed() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        harness.link.deliver("FIRST\r>SECOND\r>")
        let first = try await AdapterLinkBoundedAwait.value("readUntilPrompt") { try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(1)) }
        let second = try await AdapterLinkBoundedAwait.value("readUntilPrompt") { try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(1)) }
        XCTAssertEqual(String(decoding: first, as: UTF8.self), "FIRST\r>")
        XCTAssertEqual(String(decoding: second, as: UTF8.self), "SECOND\r>")
    }

    /// 読取の待機中に2件の応答が1回で届いても、1件目だけを返し2件目を次の読取へ残します。
    ///
    /// 責務: 待機中の受信でも応答境界 `>` で分けることを確認します。
    func testResponsesArrivingDuringPendingReadAreNotMixed() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        let task = Task { @MainActor in
            try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(600))
        }
        try await BLEBoundedWaiter.settle(polls: 5)
        harness.link.deliver("FIRST\r>SECOND\r>")
        let first = AdapterLinkBoundedAwait.successValue(await AdapterLinkBoundedAwait.outcome(of: task, "待機中の読取"))
        XCTAssertEqual(first.map { String(decoding: $0, as: UTF8.self) }, "FIRST\r>")
        let second = try await AdapterLinkBoundedAwait.value("readUntilPrompt") { try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(1)) }
        XCTAssertEqual(String(decoding: second, as: UTF8.self), "SECOND\r>")
    }

    /// 前の利用者が読まずに残したバイトは次の利用者へ漏れません。
    ///
    /// 責務: 未完の残り・読み残した完全な応答の両方が、占有者交代後の読取に含まれないことを確認します。
    func testLeftoverBytesDoNotLeakToNextLeaseHolder() async throws {
        for leftover in ["PARTIAL 41 0C", "UNREAD\r>"] {
            let harness = AdapterLinkByteStreamHarness()
            let first = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
            harness.link.deliver(leftover)
            harness.stream.release(first)
            let second = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
            harness.link.deliver("NEXT\r>")
            let data = try await AdapterLinkBoundedAwait.value("readUntilPrompt") {
                try await harness.stream.readUntilPrompt(lease: second, timeout: .seconds(1))
            }
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "NEXT\r>", "残り: \(leftover)")
        }
    }

    /// 誰も占有していない間に届いたバイトは、後の占有者の応答に含まれません。
    ///
    /// 責務: 占有者不在時の受信を捨てることを確認します。
    func testBytesReceivedWithoutHolderAreDiscarded() async throws {
        let harness = AdapterLinkByteStreamHarness()
        harness.link.deliver("STRAY\r>")
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        harness.link.deliver("OK\r>")
        let data = try await AdapterLinkBoundedAwait.value("readUntilPrompt") { try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(1)) }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "OK\r>")
    }

    /// プロンプトが来なければ上限時間で期限切れとして終わります。
    ///
    /// 責務: 受信が無いまま待つ読取が `.responseTimedOut` で終わることを確認します。
    func testReadUntilPromptTimesOutWithoutPrompt() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        harness.link.deliver("41 00 BE")
        let outcome = await AdapterLinkBoundedAwait.run("期限切れの読取") {
            try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(2))
        }
        AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.responseTimedOut)
    }

    /// 読取中にリンクが切断されると、期限切れとは別のエラーで終わります。
    ///
    /// 責務: 長い上限の読取が切断で `.linkLost` として早く終わることを確認します。
    func testReadUntilPromptFailsWithLinkLostWhenLinkDisconnects() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        let task = Task { @MainActor in
            try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(600))
        }
        try await BLEBoundedWaiter.settle(polls: 5)
        harness.link.state = AdapterLinkByteStreamHarness.disconnected
        let outcome = await AdapterLinkBoundedAwait.outcome(of: task, "切断中の読取")
        AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.linkLost)
    }

    /// 読取中のキャンセルで読取は `CancellationError` として終わります。
    ///
    /// 責務: 長い上限の読取がキャンセルで早く終わることを確認します。
    func testReadUntilPromptEndsOnCancellation() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        let task = Task { @MainActor in
            try await harness.stream.readUntilPrompt(lease: lease, timeout: .seconds(600))
        }
        try await BLEBoundedWaiter.settle(polls: 5)
        task.cancel()
        let outcome = await AdapterLinkBoundedAwait.outcome(of: task, "キャンセルした読取")
        guard case .failure(let error)? = outcome else { return XCTFail("失敗で終わるはず: \(String(describing: outcome))") }
        XCTAssertTrue(error is CancellationError, "実際のエラー: \(error)")
    }

    /// 書き込みはリンクへバイト列をそのまま、呼び出し順で渡します。
    ///
    /// 責務: 3件の書き込みが加工されずに順番どおり記録されることを確認します。
    func testWritePassesBytesUnchangedInOrder() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        let payloads = [Data("ATZ\r".utf8), Data([0x00, 0xFF, 0x3E]), Data("010C\r".utf8)]
        for payload in payloads {
            try await AdapterLinkBoundedAwait.value("write") { try await harness.stream.write(payload, lease: lease) }
        }
        XCTAssertEqual(harness.link.writes, payloads)
    }

    /// リンクが `ready` でなければ占有権を渡さず、リンクの開始も停止もしません。
    ///
    /// 責務: `ready` 以外の各状態で `.notReady` になり、`start`/`stop` が呼ばれないことを確認します。
    func testAcquireLeaseFailsWhenLinkIsNotReady() async {
        let states: [AdapterLinkState] = [.idle, .awaitingPeripheral, .connecting, .discovering, AdapterLinkByteStreamHarness.disconnected]
        for state in states {
            let harness = AdapterLinkByteStreamHarness(state: state)
            let outcome = await AdapterLinkBoundedAwait.run("未準備の占有") { try await harness.stream.acquireLease() }
            AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.notReady)
            XCTAssertEqual(harness.link.startCount, 0, "\(state)")
            XCTAssertEqual(harness.link.stopCount, 0, "\(state)")
        }
    }

    /// 解放済みの占有権では書き込めません。
    ///
    /// 責務: 解放後の書き込みが `.leaseNotHeld` で失敗し、リンクへ何も渡さないことを確認します。
    func testWriteWithReleasedLeaseFails() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let lease = try await AdapterLinkBoundedAwait.value("acquireLease") { try await harness.stream.acquireLease() }
        harness.stream.release(lease)
        let outcome = await AdapterLinkBoundedAwait.run("解放後の書き込み") {
            try await harness.stream.write(Data("ATZ\r".utf8), lease: lease)
        }
        AdapterLinkBoundedAwait.assertFailure(outcome, AdapterLinkByteStreamError.leaseNotHeld)
        XCTAssertTrue(harness.link.writes.isEmpty)
    }
}
