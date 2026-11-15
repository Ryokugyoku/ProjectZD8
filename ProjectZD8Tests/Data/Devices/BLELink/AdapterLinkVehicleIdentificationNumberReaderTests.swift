import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleIdentificationNumberReader` の VIN 取り出しと通信失敗を検証します。
@MainActor
final class AdapterLinkVehicleIdentificationNumberReaderTests: XCTestCase {
    /// 有効な VIN の例です(`1D4GP00R55B123456`)。
    private static let expectedVIN = "1D4GP00R55B123456"
    /// CAN のマルチフレームで返る `0902` の応答です(ヘッダー表示なし)。
    private static let multiFrameResponse = "014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r2: 42 31 32 33 34 35 36\r\r>"

    /// `0902` へ指定の応答を返すアダプターで VIN を読み取ります。
    ///
    /// 責務: 台本に `0902` の応答を設定し、読取を上限付きで待ちます。
    /// - Parameters:
    ///   - response: `0902` への応答。`nil` なら応答しません。
    ///   - configure: 実行前に台本を調整する処理。
    /// - Returns: 使ったハーネスと結果。
    private func read(
        response: String?,
        configure: (ScriptedAdapterLinkFake) -> Void = { _ in }
    ) async -> (AdapterLinkByteStreamHarness, Result<String?, any Error>?) {
        let harness = AdapterLinkByteStreamHarness()
        harness.link.replies["0902"] = response
        configure(harness.link)
        let reader = AdapterLinkVehicleIdentificationNumberReader(stream: harness.stream)
        let outcome = await AdapterLinkBoundedAwait.run("VIN 読取") { try await reader.readVehicleIdentificationNumber() }
        return (harness, outcome)
    }

    /// マルチフレームの `0902` 応答から17文字の VIN を返します。
    ///
    /// 責務: `0902` を送り、連続フレームを結合した VIN を返すことを確認します。
    func testMultiFrameResponseReturnsVIN() async {
        let (harness, outcome) = await read(response: Self.multiFrameResponse)
        XCTAssertEqual(AdapterLinkBoundedAwait.successValue(outcome), Self.expectedVIN)
        XCTAssertEqual(harness.link.writtenCommands, ["0902"])
    }

    /// 解析できない・17文字でない・`NO DATA` の応答は VIN 無し(`nil`)になります。
    ///
    /// 責務: 各応答で読取が成功して `nil` を返すことを確認します。
    func testUnusableResponsesReturnNil() async {
        let responses = [
            "NO DATA\r\r>",
            "GARBAGE\r\r>",
            "014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r2: 42 31 32 33 34 35\r\r>",
            "?\r\r>",
            "\r\r>"
        ]
        for response in responses {
            let (_, outcome) = await read(response: response)
            guard let value = AdapterLinkBoundedAwait.successValue(outcome) else { continue }
            XCTAssertNil(value, "応答: \(response.debugDescription)")
        }
    }

    /// 通信失敗は VIN 無しとして返さず throw します。
    ///
    /// 責務: 無応答は期限切れ(`.responseTimedOut`)、送信時の切断はリンク喪失(`.linkLost`)と、区別できる失敗になることを確認します。
    func testCommunicationFailureThrows() async {
        let (_, silent) = await read(response: nil)
        AdapterLinkBoundedAwait.assertFailure(silent, AdapterLinkByteStreamError.responseTimedOut)

        let (_, dropped) = await read(response: nil) { link in
            link.disconnectingCommands = ["0902"]
        }
        AdapterLinkBoundedAwait.assertFailure(dropped, AdapterLinkByteStreamError.linkLost)
    }
}
