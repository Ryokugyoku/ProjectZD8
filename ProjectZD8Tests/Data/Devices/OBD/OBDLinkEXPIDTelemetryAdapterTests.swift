import Foundation
import XCTest
@testable import ProjectZD8

/// OBDLink EX主要PID読取の許可コマンド列と応答保持を検証します。
@MainActor
final class OBDLinkEXPIDTelemetryAdapterTests: XCTestCase {
    /// 2種の検証済みPIDを1回の接続で読み取ります。
    ///
    /// 責務: 初期化後に0105と010Cだけを送り、応答バイトを要求別に保持することを確認します。
    func testReadsAllowlistedMajorPIDsAndClosesTransport() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "SEARCHING...\r41 05 85\r>", "41 0C 00 00\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        let requests = [
            OBDPIDRequest(service: 0x01, pid: 0x05),
            OBDPIDRequest(service: 0x01, pid: 0x0C)
        ]

        let values = try await adapter.read(requests, using: endpoint)
        await adapter.endSession()
        let commands = await transport.commands
        let didClose = await transport.didClose

        XCTAssertEqual(values[requests[0]], [0x85])
        XCTAssertEqual(values[requests[1]], [0x00, 0x00])
        XCTAssertEqual(commands, ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r", "0105\r", "010C\r"])
        XCTAssertTrue(didClose)
    }

    /// Service 01以外をTransport生成前に拒否します。
    ///
    /// 責務: 現在値取得以外のService/PIDが物理送信されないことを確認します。
    func testRejectsUnsupportedServiceBeforeOpeningTransport() async {
        let transport = PIDTransportFake(responses: [])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        do {
            _ = try await adapter.read([.init(service: 0x02, pid: 0x0C)], using: endpoint)
            XCTFail("非対応Serviceは成功してはいけません")
        } catch {
            let didOpen = await transport.didOpen
            XCTAssertEqual(error as? OBDPIDTelemetryError, .unsupportedPID)
            XCTAssertFalse(didOpen)
        }
    }

    /// シリアル応答期限切れを車両無応答として返し、Transportを閉じます。
    ///
    /// 責務: 期限切れを自動切断可能なTelemetryエラーへ変換することを確認します。
    func testTimeoutMapsToNoVehicleResponseAndClosesTransport() async {
        let transport = PIDTransportFake(responses: [])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        do {
            _ = try await adapter.read([.init(service: 0x01, pid: 0x0C)], using: endpoint)
            XCTFail("応答期限切れは成功してはいけません")
        } catch {
            let didClose = await transport.didClose
            XCTAssertEqual(error as? OBDPIDTelemetryError, .noVehicleResponse)
            XCTAssertTrue(didClose)
        }
    }

    /// テスト用EXシリアル終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.fake", displayName: "OBDLink EX")
    }
}

/// PID読取テストへ固定応答列を返すTransportです。
private actor PIDTransportFake: OBDCommandTransport {
    /// 未使用の固定応答列です。
    private var responses: [String]
    /// 送信されたコマンド履歴です。
    private(set) var commands: [String] = []
    /// openが実行されたかどうかです。
    private(set) var didOpen = false
    /// closeが実行されたかどうかです。
    private(set) var didClose = false

    /// 固定応答列を保持します。
    ///
    /// 責務: read順に返す決定的な応答列を初期化します。
    /// - Parameter responses: 各readで先頭から返す応答。
    init(responses: [String]) { self.responses = responses }

    /// open呼出しを記録します。
    ///
    /// 責務: Transportのopen事実だけを観測可能にします。
    func open() async throws { didOpen = true }

    /// 送信コマンドを記録します。
    ///
    /// 責務: 1件のASCII送信データをコマンド履歴へ追加します。
    /// - Parameter data: 送信するコマンドデータ。
    func write(_ data: Data) async throws {
        guard let command = String(data: data, encoding: .utf8) else { throw OBDPIDTelemetryError.malformedResponse }
        commands.append(command)
    }

    /// 次の固定応答を返します。
    ///
    /// 責務: 未使用応答列の先頭1件をプロンプト終端データとして返します。
    /// - Returns: 次の固定応答データ。
    func readUntilPrompt() async throws -> Data {
        guard !responses.isEmpty else { throw VehicleIdentificationError.responseTimedOut }
        return Data(responses.removeFirst().utf8)
    }

    /// close呼出しを記録します。
    ///
    /// 責務: Transportのclose事実だけを観測可能にします。
    func close() async { didClose = true }
}
