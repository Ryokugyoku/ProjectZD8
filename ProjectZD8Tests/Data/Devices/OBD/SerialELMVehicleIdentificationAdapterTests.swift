import Foundation
import XCTest
@testable import ProjectZD8

/// 選択済みELM/STN互換シリアルAdapterのコマンド順序、観測保持、失敗終端を検証します。
@MainActor
final class SerialELMVehicleIdentificationAdapterTests: XCTestCase {
    /// 完全な識別フローがVINと全原文を返します。
    ///
    /// 責務: 標準初期化、VIN、protocol要求が順序通り実行されTransportが閉じることを確認します。
    func testIdentifyExecutesAllowlistedSequenceAndPreservesRawResponses() async throws {
        let transport = OBDCommandTransportFake(responses: successfulResponses)
        let adapter = SerialELMVehicleIdentificationAdapter(
            makeTransport: { _ in transport },
            now: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = try await adapter.identifyVehicle(using: endpoint)

        let commands = await transport.commands
        let didClose = await transport.didClose
        XCTAssertEqual(snapshot.vin, "1D4GP00R55B123456")
        XCTAssertNil(snapshot.obdIdentifier)
        XCTAssertEqual(snapshot.rawResponses.count, 9)
        XCTAssertEqual(commands, ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r", "ATI\r", "0902\r", "ATDP\r"])
        XCTAssertTrue(didClose)
    }

    /// 空白埋めの実車識別子をVINと混同しません。
    ///
    /// 責務: Service 09の空白埋め値が非VINのOBD由来識別子として観測に残ることを確認します。
    func testIdentifyPreservesSpacePaddedIdentifierSeparatelyFromVIN() async throws {
        var responses = successfulResponses
        responses[7] = "014\r0: 49 02 01 20 20 20\r1: 20 20 20 20 5A 44 38\r2: 31 32 33 34 35 36 37\r>"
        let transport = OBDCommandTransportFake(responses: responses)
        let adapter = SerialELMVehicleIdentificationAdapter(makeTransport: { _ in transport })

        let snapshot = try await adapter.identifyVehicle(using: endpoint)

        XCTAssertNil(snapshot.vin)
        XCTAssertEqual(snapshot.obdIdentifier, "ZD81234567")
    }

    /// Bluetooth終端へEXシリアルコマンドを送りません。
    ///
    /// 責務: EXのUSB以外の接続方式がTransport生成前に拒否されることを確認します。
    func testRejectsNonSerialEndpointBeforeOpeningTransport() async {
        let transport = OBDCommandTransportFake(responses: [])
        let adapter = SerialELMVehicleIdentificationAdapter(makeTransport: { _ in transport })
        do {
            _ = try await adapter.identifyVehicle(using: .init(transport: .bluetoothLowEnergy, systemIdentifier: "x", displayName: "x"))
            XCTFail("EXはBLE終端へ接続してはいけません")
        } catch {
            XCTAssertEqual(
                error as? VehicleIdentificationError,
                .stageFailed(.endpointValidation, .transportUnsupported)
            )
            let didOpen = await transport.didOpen
            XCTAssertFalse(didOpen)
        }
    }

    /// NO DATA応答をVIN未取得成功へ変換しません。
    ///
    /// 責務: 車両未応答時に型付き失敗を返してTransportを閉じることを確認します。
    func testNoDataFailsAndClosesTransport() async {
        var responses = successfulResponses
        responses[7] = "NO DATA\r>"
        let transport = OBDCommandTransportFake(responses: responses)
        let adapter = SerialELMVehicleIdentificationAdapter(makeTransport: { _ in transport })
        do {
            _ = try await adapter.identifyVehicle(using: endpoint)
            XCTFail("NO DATAは成功してはいけません")
        } catch {
            XCTAssertEqual(
                error as? VehicleIdentificationError,
                .stageFailed(.vehicleIdentificationRequest, .commandRejected)
            )
            let didClose = await transport.didClose
            XCTAssertTrue(didClose)
        }
    }

    /// 製品固有コマンドなしで選択済みシリアル機器へ車両識別を要求します。
    ///
    /// 責務: `ATI` の製品名に依存せず標準 `0902` 要求へ進むことを確認します。
    func testSelectedSerialAdapterDoesNotRequireOBDLinkProductName() async throws {
        var responses = successfulResponses
        responses[6] = "ELM327 compatible\r>"
        let transport = OBDCommandTransportFake(responses: responses)
        let adapter = SerialELMVehicleIdentificationAdapter(makeTransport: { _ in transport })

        _ = try await adapter.identifyVehicle(using: endpoint)

        let commands = await transport.commands
        XCTAssertTrue(commands.contains("0902\r"))
        XCTAssertFalse(commands.contains("STDIX\r"))
    }

    /// テスト用EXシリアル終端です。
    private var endpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.fake", displayName: "OBDLink EX")
    }

    /// 全許可コマンドへ対応する成功応答です。
    private var successfulResponses: [String] {
        [
            "OBDLink EX 5.9.1\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>", "OK\r>",
            "ELM327 v1.4b\r>",
            "014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r2: 42 31 32 33 34 35 36\r>",
            "AUTO, ISO 15765-4 (CAN 11/500)\r>"
        ]
    }
}

/// EX識別テストへ決定的なコマンド応答列を返します。
private actor OBDCommandTransportFake: OBDCommandTransport {
    /// 順番に返す加工前応答です。
    private var responses: [String]
    /// 書き込まれたASCIIコマンドです。
    private(set) var commands: [String] = []
    /// openが呼ばれたかどうかです。
    private(set) var didOpen = false
    /// closeが呼ばれたかどうかです。
    private(set) var didClose = false

    /// 応答列を保持して生成します。
    ///
    /// 責務: 1件のテストシナリオに必要な応答順序を固定します。
    /// - Parameter responses: readごとに先頭から返す応答。
    init(responses: [String]) { self.responses = responses }

    /// Fake終端をopen済みにします。
    ///
    /// 責務: open呼出しを観測可能な真偽値へ記録します。
    func open() async throws { didOpen = true }

    /// 送信コマンドを記録します。
    ///
    /// 責務: 1件の書込みバイトをASCIIコマンド履歴へ追加します。
    /// - Parameter data: 送信されたASCIIデータ。
    func write(_ data: Data) async throws {
        guard let command = String(data: data, encoding: .utf8) else { throw VehicleIdentificationError.malformedResponse }
        commands.append(command)
    }

    /// 次の固定応答を返します。
    ///
    /// 責務: 現在シナリオの未使用応答を先頭から1件返します。
    /// - Returns: UTF-8応答データ。
    func readUntilPrompt() async throws -> Data {
        guard !responses.isEmpty else { throw VehicleIdentificationError.responseTimedOut }
        return Data(responses.removeFirst().utf8)
    }

    /// Fake終端をclose済みにします。
    ///
    /// 責務: close呼出しを観測可能な真偽値へ記録します。
    func close() async { didClose = true }
}
