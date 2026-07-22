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
            "OK\r>", "SEARCHING...\r41 05 85\r>", "41 0C 00 00\r>"
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
        XCTAssertEqual(commands, ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r", "ATSH7DF\r", "0105\r", "010C\r"])
        XCTAssertTrue(didClose)
    }

    /// ZD8専用PIDを定義済み物理ヘッダーへ送信します。
    ///
    /// 責務: 車種専用定義が7E0と7E1へ個別送信され、正応答だけを保持することを確認します。
    func testReadsZD8PIDsWithDefinitionHeaders() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "OK\r>", "61 02 00 01 E2 40\r>", "OK\r>", "61 17 76\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        let values = try await adapter.readVehicleSpecific(ZD8OBDPIDSeed.definitions, using: endpoint)
        await adapter.endSession()
        let commands = await transport.commands

        XCTAssertEqual(values[.init(service: 0x21, pid: 0x02)], [0x00, 0x01, 0xE2, 0x40])
        XCTAssertEqual(values[.init(service: 0x21, pid: 0x17)], [0x76])
        XCTAssertTrue(commands.contains("ATSH7E0\r"))
        XCTAssertTrue(commands.contains("2102\r"))
        XCTAssertTrue(commands.contains("ATSH7E1\r"))
        XCTAssertTrue(commands.contains("2117\r"))
    }

    /// OBDLinkへ回転数と車速の周期送信を登録して受信します。
    ///
    /// 責務: Beta取得が2件の固定STPPMAと有限STMだけを送ることを確認します。
    func testReadsBRZBetaPIDsUsingPeriodicMessaging() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "OK\r>", "1\r>", "2\r>", "41 0C 1F 40\r41 0D 32\r>", "OK\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        let values = try await adapter.readPeriodic(BRZBetaPIDPolicy.requests, using: endpoint)
        await adapter.endSession()
        let commands = await transport.commands

        XCTAssertEqual(values[OBDPIDRequest(service: 0x01, pid: 0x0C)]?.prefix(2), [0x1F, 0x40])
        XCTAssertEqual(values[OBDPIDRequest(service: 0x01, pid: 0x0D)]?.first, 0x32)
        XCTAssertEqual(
            commands,
            [
                "ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r",
                "STPPMC\r", "STPPMA 100,7DF,010C\r", "STPPMA 100,7DF,010D\r", "STM 2\r", "STPPMC\r"
            ]
        )
    }

    /// Beta以外の要求集合をシリアル接続前に拒否します。
    ///
    /// 責務: 未許可PIDがSTN周期メッセージへ変換されないことを確認します。
    func testRejectsNonBetaPeriodicRequestsBeforeOpeningTransport() async {
        let transport = PIDTransportFake(responses: [])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        do {
            _ = try await adapter.readPeriodic([.init(service: 0x01, pid: 0x05)], using: endpoint)
            XCTFail("対象外PIDの周期送信は成功してはいけません")
        } catch {
            let didOpen = await transport.didOpen
            XCTAssertEqual(error as? OBDPIDTelemetryError, .periodicMessagingUnavailable)
            XCTAssertFalse(didOpen)
        }
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
