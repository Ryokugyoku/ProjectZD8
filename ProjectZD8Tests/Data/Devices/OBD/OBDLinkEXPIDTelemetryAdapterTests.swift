import Foundation
import XCTest
@testable import ProjectZD8

/// OBDLink EX／MX+主要PID読取の許可コマンド列と応答保持を検証します。
@MainActor
final class OBDLinkEXPIDTelemetryAdapterTests: XCTestCase {
    /// 拒否文字列と正応答を要求単位で区別します。
    ///
    /// 責務: NO DATAを非対応と推測せず未分類応答として保持し、後続正応答を失わないことを確認します。
    func testReadObservationsKeepsRejectedResponseUnclassifiedAndContinues() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "OK\r>", "NO DATA\r>", "41 0C 1F 40\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        let requests = [
            OBDPIDRequest(service: 0x01, pid: 0x05),
            OBDPIDRequest(service: 0x01, pid: 0x0C)
        ]

        let observations = try await adapter.readObservations(requests, using: endpoint)

        XCTAssertEqual(observations, [
            .init(request: requests[0], outcome: .unclassifiedResponse),
            .init(request: requests[1], outcome: .responded([0x1F, 0x40]))
        ])
    }

    /// 送信後の期限切れを該当要求だけへ対応付けます。
    ///
    /// 責務: 期限切れ要求をtyped結果として残し、未送信の後続要求を観測済みにしないことを確認します。
    func testReadObservationsStopsAfterTypedTimeout() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        let requests = [
            OBDPIDRequest(service: 0x01, pid: 0x05),
            OBDPIDRequest(service: 0x01, pid: 0x0C)
        ]

        let observations = try await adapter.readObservations(requests, using: endpoint)
        let didClose = await transport.didClose

        XCTAssertEqual(observations, [.init(request: requests[0], outcome: .timedOut)])
        XCTAssertTrue(didClose)
    }

    /// 空のPID要求では物理接続を開きません。
    ///
    /// 責務: 空バッチをBluetoothまたはシリアル接続なしの空応答へ変換することを確認します。
    func testEmptyBatchDoesNotOpenTransport() async throws {
        let transport = PIDTransportFake(responses: [])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        let values = try await adapter.read([], using: endpoint)

        let didOpen = await transport.didOpen
        XCTAssertEqual(values, [:])
        XCTAssertFalse(didOpen)
    }

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

    /// MX+のBluetooth Classic終端からも許可済み主要PIDを読み取ります。
    ///
    /// 責務: Bluetooth Classic終端がELM/STNバイトストリームとして主要PID取得へ進むことを確認します。
    func testReadsAllowlistedPIDThroughBluetoothClassicByteStream() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "OK\r>", "41 0C 1F 40\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        let request = OBDPIDRequest(service: 0x01, pid: 0x0C)
        let endpoint = OBDConnectionEndpoint(
            transport: .bluetoothClassic,
            systemIdentifier: "00-04-3E-12-34-56",
            displayName: "OBDLink MX+ 48318"
        )

        let values = try await adapter.read([request], using: endpoint)
        await adapter.endSession()

        XCTAssertEqual(values[request], [0x1F, 0x40])
        let didOpen = await transport.didOpen
        XCTAssertTrue(didOpen)
    }

    /// 既知UARTを提供するBLE終端から許可済み主要PIDを読み取ります。
    ///
    /// 責務: BLE UART終端が主要PID取得の共通ELM/STNチャネルへ進むことを確認します。
    func testReadsAllowlistedPIDThroughBluetoothLowEnergyByteStream() async throws {
        let transport = PIDTransportFake(responses: [
            "ELM327 v1.4b\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "OK\r>", "41 0C 1F 40\r>"
        ])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })
        let request = OBDPIDRequest(service: 0x01, pid: 0x0C)
        let endpoint = OBDConnectionEndpoint(
            transport: .bluetoothLowEnergy,
            systemIdentifier: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            displayName: "OBDLink BLE candidate"
        )

        let values = try await adapter.read([request], using: endpoint)
        await adapter.endSession()

        XCTAssertEqual(values[request], [0x1F, 0x40])
        let didOpen = await transport.didOpen
        XCTAssertTrue(didOpen)
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

    /// ELM初期化拒否時はPID要求へ進まずTransportを閉じます。
    ///
    /// 責務: 1件の拒否された初期化応答を接続資源解放済みのコマンド拒否へ変換することを確認します。
    func testRejectedInitializationClosesTransportBeforePIDRequest() async {
        let transport = PIDTransportFake(responses: ["ELM327 v1.4b\r>", "?\r>"])
        let adapter = OBDLinkEXPIDTelemetryAdapter(makeTransport: { _ in transport })

        do {
            _ = try await adapter.read([.init(service: 0x01, pid: 0x0C)], using: endpoint)
            XCTFail("初期化拒否は成功してはいけません")
        } catch {
            let commands = await transport.commands
            let didClose = await transport.didClose
            XCTAssertEqual(error as? OBDPIDTelemetryError, .commandRejected)
            XCTAssertEqual(commands, ["ATZ\r", "ATE0\r"])
            XCTAssertTrue(didClose)
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
