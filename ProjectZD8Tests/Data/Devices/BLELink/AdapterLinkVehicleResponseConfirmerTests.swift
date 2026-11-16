import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleResponseConfirmer` の応答判定・タイムアウト設定・通信失敗を検証します。
@MainActor
final class AdapterLinkVehicleResponseConfirmerTests: XCTestCase {
    /// `0100` へ指定の応答を返すアダプターで車両確認を実行します。
    ///
    /// 責務: 設定コマンドを受け付ける台本に `0100` の応答を差し込み、確認を上限付きで待ちます。
    /// - Parameters:
    ///   - response: `0100` への応答。`nil` なら応答しません。
    ///   - timeout: 確認のタイムアウト種別。
    ///   - configure: 実行前に台本を調整する処理。
    /// - Returns: 使ったハーネスと結果。
    private func confirm(
        response: String?,
        timeout: VehicleResponseTimeout = .standard,
        configure: (ScriptedAdapterLinkFake) -> Void = { _ in }
    ) async -> (AdapterLinkByteStreamHarness, Result<VehicleResponseOutcome, any Error>?) {
        let harness = AdapterLinkByteStreamHarness()
        var replies = AdapterLinkELMReplyFixtures.initializableAdapter(
            stnIdentity: AdapterLinkELMReplyFixtures.stnIdentity,
            adapterIdentity: AdapterLinkELMReplyFixtures.elmVersion15
        )
        replies["0100"] = response
        harness.link.replies = replies
        configure(harness.link)
        let confirmer = AdapterLinkVehicleResponseConfirmer(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("車両確認") { try await confirmer.confirmVehicleResponse(timeout: timeout) }
        return (harness, outcome)
    }

    /// ECU の正応答 `41 00 …` があった時だけ「応答あり」になります。
    ///
    /// 責務: 空白・大文字小文字・`SEARCHING...` 前置きの違いがあっても正応答を「応答あり」と判定することを確認します。
    func testPositiveResponseIsResponding() async {
        let responses = [
            "41 00 BE 3E B8 13 \r\r>",
            "4100BE3EB813\r\r>",
            "41 00 be 3e b8 13\r\r>",
            "SEARCHING...\r41 00 BE 3E B8 13 \r\r>",
            "searching...\r4100be3eb813\r\r>"
        ]
        for response in responses {
            let (_, outcome) = await confirm(response: response)
            XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding, "応答: \(response.debugDescription)")
        }
    }

    /// 正応答でない応答はすべて「無応答」になります。
    ///
    /// 責務: NO DATA・UNABLE TO CONNECT・SEARCHING のみ・バスエラー系・`?`・空応答を、大文字小文字の違いも含めて確認します。
    func testNonPositiveResponsesAreNoResponse() async {
        let responses = [
            "NO DATA\r\r>",
            "no data\r\r>",
            "UNABLE TO CONNECT\r\r>",
            "SEARCHING...\r\r>",
            "SEARCHING...\rUNABLE TO CONNECT\r\r>",
            "BUS INIT: ...ERROR\r\r>",
            "BUS ERROR\r\r>",
            "CAN ERROR\r\r>",
            "can error\r\r>",
            "?\r\r>",
            "\r\r>",
            ">"
        ]
        for response in responses {
            let (_, outcome) = await confirm(response: response)
            XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .noResponse, "応答: \(response.debugDescription)")
        }
    }

    /// `.adapterMaximum` ではアダプター側タイムアウトを最大にしてから `0100` を送ります。
    ///
    /// 責務: `ATSTFF` が `0100` より前に送られることを確認します。
    func testAdapterMaximumSetsMaximumTimeoutBeforeRequest() async throws {
        let (harness, outcome) = await confirm(response: AdapterLinkELMReplyFixtures.supportedPIDsPositive, timeout: .adapterMaximum)
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding)
        let commands = harness.link.writtenCommands
        let maximum = try XCTUnwrap(commands.firstIndex(of: "ATSTFF"))
        let request = try XCTUnwrap(commands.firstIndex(of: "0100"))
        XCTAssertLessThan(maximum, request)
    }

    /// `.heldWatch`(抑止中の見張り)では、適応タイミングを切り、アダプター側タイムアウトを最大にしてから `0100` を送ります。
    ///
    /// 責務: `ATAT0` → `ATSTFF` → `0100` の順に送られ、正応答が「応答あり」になることを確認します(U3 受け入れ条件 9)。
    func testHeldWatchDisablesAdaptiveTimingThenSetsMaximumBeforeRequest() async throws {
        let (harness, outcome) = await confirm(response: AdapterLinkELMReplyFixtures.supportedPIDsPositive, timeout: .heldWatch) { link in
            link.replies["ATAT0"] = "OK\r\r>"
        }
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding)
        let commands = harness.link.writtenCommands
        let adaptive = try XCTUnwrap(commands.firstIndex(of: "ATAT0"))
        let maximum = try XCTUnwrap(commands.firstIndex(of: "ATSTFF"))
        let request = try XCTUnwrap(commands.firstIndex(of: "0100"))
        XCTAssertLessThan(adaptive, maximum)
        XCTAssertLessThan(maximum, request)
    }

    /// `ATAT0` を受け付けないアダプター(`?` を返す)でも、見張りの確認は失敗にならず `ATSTFF` と `0100` を送ります。
    ///
    /// 責務: `ATAT0` に `?` が返っても、続けて `ATSTFF` と `0100` が送られ、無応答・応答ありの判定が返ることを確認します(U3 受け入れ条件 9)。
    func testHeldWatchContinuesWhenAdaptiveTimingIsRejected() async throws {
        for (response, expected) in [(AdapterLinkELMReplyFixtures.supportedPIDsPositive, VehicleResponseOutcome.responding), ("NO DATA\r\r>", .noResponse)] {
            let (harness, outcome) = await confirm(response: response, timeout: .heldWatch) { link in
                link.replies["ATAT0"] = "?\r\r>"
            }
            XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), expected, response.debugDescription)
            XCTAssertTrue(harness.link.writtenCommands.contains("ATSTFF"), response.debugDescription)
            XCTAssertTrue(harness.link.writtenCommands.contains("0100"), response.debugDescription)
        }
    }

    /// `.standard` と `.adapterMaximum` では、適応タイミングを変えません。
    ///
    /// 責務: `ATAT0` を送らないことを確認します。
    func testNonWatchTimeoutsDoNotChangeAdaptiveTiming() async {
        for timeout in [VehicleResponseTimeout.standard, .adapterMaximum] {
            let (harness, _) = await confirm(response: AdapterLinkELMReplyFixtures.supportedPIDsPositive, timeout: timeout)
            XCTAssertFalse(harness.link.writtenCommands.contains("ATAT0"), "\(timeout)")
        }
    }

    /// `.standard` ではアダプター側タイムアウトを最大にしません。
    ///
    /// 責務: `ATSTFF` を送らずに `0100` を送ることを確認します。
    func testStandardDoesNotSetMaximumTimeout() async {
        let (harness, outcome) = await confirm(response: AdapterLinkELMReplyFixtures.supportedPIDsPositive, timeout: .standard)
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), .responding)
        XCTAssertFalse(harness.link.writtenCommands.contains("ATSTFF"))
        XCTAssertTrue(harness.link.writtenCommands.contains("0100"))
    }

    /// 通信失敗は「無応答」として返さず throw します。
    ///
    /// 責務: タイムアウト種別によらず、`0100` の無応答は期限切れ(`.responseTimedOut`)、送信時の切断はリンク喪失(`.linkLost`)になることを確認します。
    func testCommunicationFailureThrowsInsteadOfNoResponse() async {
        for timeout in [VehicleResponseTimeout.standard, .adapterMaximum] {
            let (_, silent) = await confirm(response: nil, timeout: timeout)
            AdapterLinkBoundedAwait.assertFailure(silent, AdapterLinkByteStreamError.responseTimedOut)

            let (_, dropped) = await confirm(response: nil, timeout: timeout) { link in
                link.disconnectingCommands = ["0100"]
            }
            AdapterLinkBoundedAwait.assertFailure(dropped, AdapterLinkByteStreamError.linkLost)
        }
    }
}
