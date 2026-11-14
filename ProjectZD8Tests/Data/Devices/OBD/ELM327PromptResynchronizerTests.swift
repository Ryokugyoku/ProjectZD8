import Foundation
import XCTest
@testable import ProjectZD8

/// プロンプト再同期が ATI を送り、ELM/STN を含む応答まで最大2回読むことを検証します。
@MainActor
final class ELM327PromptResynchronizerTests: XCTestCase {
    /// 1回目の応答に ELM があれば、ATI を1回送って1回だけ読みます。大文字小文字は区別しません。
    ///
    /// 責務: 送信コマンドと読み取り回数を確認します。
    func testFirstIdentityResponseSucceeds() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: ["elm327 v1.4b\r>", "unused\r>"])

        try await ELM327PromptResynchronizer().resync(transport)

        XCTAssertEqual(transport.commands, [String(decoding: ELM327Command.adapterIdentity.encodedData, as: UTF8.self)])
        let remaining = try await transport.readUntilPrompt()
        XCTAssertEqual(remaining, Data("unused\r>".utf8))
    }

    /// 1回目が古い応答でも、2回目に STN があれば成功します。
    ///
    /// 責務: 読み取り上限の2回目で成功することを確認します。
    func testSecondReadWithSTNSucceeds() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: ["41 0C 1F 40\r>", "STN1110 v4.0\r>"])

        try await ELM327PromptResynchronizer().resync(transport)

        XCTAssertEqual(transport.commands.count, 1)
    }

    /// 2回読んでも識別応答が無ければ応答期限切れで失敗し、3回目は読みません。
    ///
    /// 責務: 読み取り上限で止まり、回復の期限切れとして失敗することを確認します。
    func testTwoNonIdentityReadsTimeOut() async throws {
        let transport = ScriptedOBDCommandTransportFake(responses: ["NO DATA\r>", "?\r>", "ELM327\r>"])

        do {
            try await ELM327PromptResynchronizer().resync(transport)
            XCTFail("識別応答が無いのに成功しました")
        } catch {
            XCTAssertEqual(error as? LiveTelemetryLinkRecoveryError, .timedOut)
        }
        XCTAssertEqual(ELM327PromptResynchronizer.maximumReads, 2)
        let remaining = try await transport.readUntilPrompt()
        XCTAssertEqual(remaining, Data("ELM327\r>".utf8))
    }

    /// 読み取りの失敗はそのまま送出します。
    ///
    /// 責務: Transportの応答期限切れを握りつぶさないことを確認します。
    func testReadFailurePropagates() async {
        let transport = ScriptedOBDCommandTransportFake(responses: [])

        do {
            try await ELM327PromptResynchronizer().resync(transport)
            XCTFail("読み取り失敗なのに成功しました")
        } catch {
            XCTAssertEqual(error as? VehicleIdentificationError, .responseTimedOut)
        }
    }
}
