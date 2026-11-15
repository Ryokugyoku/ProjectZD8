import XCTest
@testable import ProjectZD8

/// `AdapterLinkOBDCommandTransport` がリンクを開始・停止せずに常駐リンクを共用することを検証します。
@MainActor
final class AdapterLinkOBDCommandTransportTests: XCTestCase {
    /// リンクが `ready` でなければ `open()` は型付きエラーで失敗し、リンクを開始も停止もしません。
    ///
    /// 責務: `ready` 以外の各状態で `open()` が `VehicleIdentificationError` になり、`start`/`stop` 0回であることを確認します。
    func testOpenFailsWithoutTouchingLinkWhenNotReady() async {
        let states: [AdapterLinkState] = [.idle, .awaitingPeripheral, .connecting, .discovering, AdapterLinkByteStreamHarness.disconnected]
        for state in states {
            let harness = AdapterLinkByteStreamHarness(state: state)
            let transport = AdapterLinkOBDCommandTransport(stream: harness.stream)
            let outcome = await AdapterLinkBoundedAwait.run("未準備の open") { try await transport.open() }
            AdapterLinkBoundedAwait.assertFailure(outcome, VehicleIdentificationError.connectionFailed)
            XCTAssertEqual(harness.link.startCount, 0, "\(state)")
            XCTAssertEqual(harness.link.stopCount, 0, "\(state)")
        }
    }

    /// 開いていない、または `ready` でなくなったトランスポートの書き込みは失敗し、何も送りません。
    ///
    /// 責務: 未オープンと、オープン後の切断の両方で `write` が型付きエラーになり、リンクを開始も停止もしないことを確認します。
    func testWriteFailsWhenNotOpenedOrLinkNotReady() async throws {
        let unopened = AdapterLinkByteStreamHarness()
        let unopenedTransport = AdapterLinkOBDCommandTransport(stream: unopened.stream)
        let unopenedOutcome = await AdapterLinkBoundedAwait.run("未オープンの書き込み") {
            try await unopenedTransport.write(Data("0100\r".utf8))
        }
        AdapterLinkBoundedAwait.assertFailure(unopenedOutcome, VehicleIdentificationError.connectionFailed)
        XCTAssertTrue(unopened.link.writes.isEmpty)

        let dropped = AdapterLinkByteStreamHarness()
        let droppedTransport = AdapterLinkOBDCommandTransport(stream: dropped.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await droppedTransport.open() }
        dropped.link.state = AdapterLinkByteStreamHarness.disconnected
        let droppedOutcome = await AdapterLinkBoundedAwait.run("切断後の書き込み") {
            try await droppedTransport.write(Data("0100\r".utf8))
        }
        AdapterLinkBoundedAwait.assertFailure(droppedOutcome, VehicleIdentificationError.connectionFailed)
        XCTAssertTrue(dropped.link.writes.isEmpty)
        XCTAssertEqual(dropped.link.startCount + dropped.link.stopCount, 0)
    }

    /// `close()` はリンクを止めず、閉じた後は別の利用者がリンクを使えます。
    ///
    /// 責務: `close()` 後もリンクが `ready`・`stop` 0回で、2つ目のトランスポートが送受信できることを確認します。
    func testCloseKeepsLinkReadyAndAllowsAnotherUser() async throws {
        let harness = AdapterLinkByteStreamHarness()
        harness.link.replies = ["010C": "41 0C 1A F8 \r\r>"]
        let first = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await first.open() }
        try await AdapterLinkBoundedAwait.value("close") { await first.close() }
        XCTAssertEqual(harness.link.state, .ready)
        XCTAssertEqual(harness.link.stopCount, 0)
        XCTAssertEqual(harness.link.startCount, 0)

        let second = AdapterLinkOBDCommandTransport(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("2人目の送受信") {
            try await second.open()
            try await second.write(Data("010C\r".utf8))
            return try await second.readUntilPrompt()
        }
        let data = AdapterLinkBoundedAwait.successValue(outcome)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "41 0C 1A F8 \r\r>")
    }

    /// 前の利用者の読み残しは次のトランスポートの応答へ混ざりません。
    ///
    /// 責務: 1つ目が読まずに閉じた受信が、2つ目の最初の応答に含まれないことを確認します。
    func testPreviousUsersLeftoverDoesNotLeakIntoNextTransport() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let first = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await first.open() }
        harness.link.deliver("41 0D 3C\r\r>41 0C")
        try await AdapterLinkBoundedAwait.value("close") { await first.close() }

        let second = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await second.open() }
        harness.link.deliver("41 05 7B\r\r>")
        let data = try await AdapterLinkBoundedAwait.value("readUntilPrompt") { try await second.readUntilPrompt() }
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "41 05 7B\r\r>")
    }

    /// 期限切れと切断は、読取を必ず終わらせ、互いに区別できるエラーになります。
    ///
    /// 責務: 無応答は `.responseTimedOut`、読取中の切断は `.connectionFailed` で終わることを確認します。
    func testReadUntilPromptDistinguishesTimeoutFromDisconnect() async throws {
        let silent = AdapterLinkByteStreamHarness()
        let silentTransport = AdapterLinkOBDCommandTransport(stream: silent.stream, responseTimeout: .seconds(2))
        try await AdapterLinkBoundedAwait.value("open") { try await silentTransport.open() }
        let timeout = await AdapterLinkBoundedAwait.run("無応答の読取") { try await silentTransport.readUntilPrompt() }
        AdapterLinkBoundedAwait.assertFailure(timeout, VehicleIdentificationError.responseTimedOut)

        let dropped = AdapterLinkByteStreamHarness()
        let droppedTransport = AdapterLinkOBDCommandTransport(stream: dropped.stream, responseTimeout: .seconds(600))
        try await AdapterLinkBoundedAwait.value("open") { try await droppedTransport.open() }
        let task = Task { @MainActor in try await droppedTransport.readUntilPrompt() }
        try await BLEBoundedWaiter.settle(polls: 5)
        dropped.link.state = AdapterLinkByteStreamHarness.disconnected
        let disconnect = await AdapterLinkBoundedAwait.outcome(of: task, "切断中の読取")
        AdapterLinkBoundedAwait.assertFailure(disconnect, VehicleIdentificationError.connectionFailed)
        XCTAssertEqual(dropped.link.stopCount, 0)
    }

    /// 読取中のキャンセルで `readUntilPrompt()` は終わります。
    ///
    /// 責務: 長い上限の読取が `CancellationError` で早く終わることを確認します。
    func testReadUntilPromptEndsOnCancellation() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let transport = AdapterLinkOBDCommandTransport(stream: harness.stream, responseTimeout: .seconds(600))
        try await AdapterLinkBoundedAwait.value("open") { try await transport.open() }
        let task = Task { @MainActor in try await transport.readUntilPrompt() }
        try await BLEBoundedWaiter.settle(polls: 5)
        task.cancel()
        let outcome = await AdapterLinkBoundedAwait.outcome(of: task, "キャンセルした読取")
        guard case .failure(let error)? = outcome else { return XCTFail("失敗で終わるはず: \(String(describing: outcome))") }
        XCTAssertTrue(error is CancellationError, "実際のエラー: \(error)")
    }

    /// 書き込みはリンクへ渡したバイト列をそのまま、呼び出し順で送ります。
    ///
    /// 責務: 3件の書き込みが加工されずに順番どおりリンクへ届くことを確認します。
    func testWriteSendsBytesUnchangedInCallOrder() async throws {
        let harness = AdapterLinkByteStreamHarness()
        let transport = AdapterLinkOBDCommandTransport(stream: harness.stream)
        try await AdapterLinkBoundedAwait.value("open") { try await transport.open() }
        let payloads = [Data("ATZ\r".utf8), Data("010C\r".utf8), Data("010D\r".utf8)]
        for payload in payloads {
            try await AdapterLinkBoundedAwait.value("write") { try await transport.write(payload) }
        }
        XCTAssertEqual(harness.link.writes, payloads)
    }
}
