import XCTest
@testable import ProjectZD8

/// 台本つきTransport上の `ELM327OBDLink` の初期化・識別・問い合わせ・切断の挙動を検証します。
@MainActor
final class ELM327OBDLinkTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let rpm = OBDPIDRequest(service: 0x01, pid: 0x0C)
    private let speed = OBDPIDRequest(service: 0x01, pid: 0x0D)
    private let odometer = OBDPIDRequest(service: 0x21, pid: 0x02)

    private func connect(
        _ transport: DevicesScriptedOBDTransport
    ) async throws -> ELM327OBDLink {
        let date = observedAt
        return try await ELM327OBDLink.connect(transport: transport, now: { date })
    }

    /// 責務: 接続時にATZ、ATE0、ATL0、ATS1、ATH0、ATSP0をこの順に送ることを確認します。
    func testInitializationSequence() async throws {
        let transport = DevicesScriptedOBDTransport()
        _ = try await connect(transport)

        let commands = transport.writtenCommands
        let openCount = transport.openCount
        XCTAssertEqual(commands, ["ATZ", "ATE0", "ATL0", "ATS1", "ATH0", "ATSP0"])
        XCTAssertEqual(openCount, 1)
    }

    /// 責務: 初期化コマンドが拒否されたら `adapterRejected` で失敗し、Transportを閉じることを確認します。
    func testInitializationRejectionClosesTransport() async {
        let transport = DevicesScriptedOBDTransport(scripts: ["ATE0": [.response("?")]])
        do {
            _ = try await connect(transport)
            XCTFail("初期化の拒否が成功扱いになった")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .adapterRejected)
        }
        let closeCount = transport.closeCount
        XCTAssertEqual(closeCount, 1)
    }

    /// 責務: Transportを開けない場合に `connectionFailed` となることを確認します。
    func testOpenFailureMapsToConnectionFailed() async {
        let transport = DevicesScriptedOBDTransport(openError: .connectionFailed)
        do {
            _ = try await connect(transport)
            XCTFail("開通失敗が成功扱いになった")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .connectionFailed)
        }
    }

    /// 責務: 非対応のTransportが `transportUnsupported` として伝わることを確認します。
    func testUnsupportedTransportMapsThrough() async {
        let transport = DevicesScriptedOBDTransport(openError: .transportUnsupported)
        do {
            _ = try await connect(transport)
            XCTFail("非対応が成功扱いになった")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .transportUnsupported)
        }
    }

    /// 責務: 初期化中の応答期限切れが `timedOut` になることを確認します。
    func testInitializationTimeout() async {
        let transport = DevicesScriptedOBDTransport(scripts: ["ATZ": [.timeout]])
        do {
            _ = try await connect(transport)
            XCTFail("期限切れが成功扱いになった")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .timedOut)
        }
    }

    /// 責務: identifyがATI、0902、ATDPの順に送り、VINとアダプター・プロトコルを返すことを確認します。
    func testIdentifyReadsAdapterVINAndProtocol() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "ATI": [.response("ELM327 v1.5")],
            "0902": [.response("014\r0: 49 02 01 4A 46 31\r1: 5A 44 38 41 41 30 50\r2: 30 30 30 30 30 30 31")],
            "ATDP": [.response("AUTO, ISO 15765-4 (CAN 11/500)")]
        ])
        let link = try await connect(transport)

        let identification = try await link.identify()

        XCTAssertEqual(identification.vin, "JF1ZD8AA0P0000001")
        XCTAssertEqual(identification.adapterDescription, "ELM327 v1.5")
        XCTAssertEqual(identification.protocolDescription, "AUTO, ISO 15765-4 (CAN 11/500)")
        XCTAssertEqual(identification.observedAt, observedAt)
        let commands = transport.writtenCommands
        XCTAssertEqual(Array(commands.dropFirst(6)), ["ATI", "ATSH7DF", "0902", "ATDP"])
    }

    /// 責務: VINが得られない場合に `vinUnavailable` を投げることを確認します。
    func testIdentifyThrowsWhenVINMissing() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: ["0902": [.response("NO DATA")]])
        let link = try await connect(transport)
        do {
            _ = try await link.identify()
            XCTFail("VINが無いのに成功した")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .vinUnavailable)
        }
    }

    /// 責務: サービス01は機能アドレス(ATSH7DF)で送り、同じヘッダーでは再送しないことを確認します。
    func testStandardQueryUsesFunctionalAddressOnce() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "010C": [.response("41 0C 1A F8")],
            "010D": [.response("41 0D 32")]
        ])
        let link = try await connect(transport)

        let first = try await link.query(rpm, header: nil)
        let second = try await link.query(speed, header: nil)

        XCTAssertEqual(first, OBDQueryResult(outcome: .responded, payload: [0x1A, 0xF8]))
        XCTAssertEqual(second, OBDQueryResult(outcome: .responded, payload: [0x32]))
        let commands = transport.writtenCommands
        XCTAssertEqual(Array(commands.dropFirst(6)), ["ATSH7DF", "010C", "010D"])
    }

    /// 責務: サービス21は指定ヘッダーへ切り替え、標準PIDへ戻る時だけ再度切り替えることを確認します。
    func testHeaderSwitchingTracksActiveHeader() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "2102": [.response("61 02 00 07 6A 3C"), .response("61 02 00 07 6A 3D")],
            "010C": [.response("41 0C 0B B8")]
        ])
        let link = try await connect(transport)

        let first = try await link.query(odometer, header: 0x7E0)
        let second = try await link.query(odometer, header: 0x7E0)
        _ = try await link.query(rpm, header: nil)

        XCTAssertEqual(first.payload, [0x00, 0x07, 0x6A, 0x3C])
        XCTAssertEqual(second.payload, [0x00, 0x07, 0x6A, 0x3D])
        let commands = transport.writtenCommands
        XCTAssertEqual(Array(commands.dropFirst(6)), ["ATSH7E0", "2102", "2102", "ATSH7DF", "010C"])
    }

    /// 責務: NO DATAが `.noData` になることを確認します。
    func testNoDataOutcome() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: ["010C": [.response("NO DATA")]])
        let link = try await connect(transport)
        let result = try await link.query(rpm, header: nil)
        XCTAssertEqual(result, OBDQueryResult(outcome: .noData))
    }

    /// 責務: 読取期限切れが `.timedOut` になり、リンクは使い続けられることを確認します。
    func testTimeoutOutcomeKeepsLinkUsable() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "010C": [.timeout],
            "010D": [.response("41 0D 10")]
        ])
        let link = try await connect(transport)

        let timedOut = try await link.query(rpm, header: nil)
        let next = try await link.query(speed, header: nil)

        XCTAssertEqual(timedOut, OBDQueryResult(outcome: .timedOut))
        XCTAssertEqual(next, OBDQueryResult(outcome: .responded, payload: [0x10]))
    }

    /// 責務: 解釈できない応答が `.failed` になることを確認します。
    func testUnparseableResponseFails() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "010C": [.response("garbage")],
            "010D": [.response("BUS ERROR")]
        ])
        let link = try await connect(transport)
        let garbage = try await link.query(rpm, header: nil)
        let busError = try await link.query(speed, header: nil)
        XCTAssertEqual(garbage, OBDQueryResult(outcome: .failed))
        XCTAssertEqual(busError, OBDQueryResult(outcome: .failed))
    }

    /// 責務: 直前のタイムアウトの遅延応答を読み捨て、今回の応答を取り出すことを確認します。
    func testStaleResponseIsDiscarded() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "010D": [.lateResponse(stale: "41 0C 1A F8", actual: "41 0D 32")]
        ])
        let link = try await connect(transport)
        let result = try await link.query(speed, header: nil)
        XCTAssertEqual(result, OBDQueryResult(outcome: .responded, payload: [0x32]))
    }

    /// 責務: 読み取り専用のため、サービス01と21以外は送信せず `.failed` とすることを確認します。
    func testOtherServicesAreRefusedWithoutSending() async throws {
        let transport = DevicesScriptedOBDTransport()
        let link = try await connect(transport)

        let clear = try await link.query(OBDPIDRequest(service: 0x04, pid: 0x00), header: nil)
        let mode22 = try await link.query(OBDPIDRequest(service: 0x22, pid: 0x01), header: 0x7E0)
        let noHeader = try await link.query(odometer, header: nil)
        let badHeader = try await link.query(odometer, header: 0x800)

        XCTAssertEqual([clear, mode22, noHeader, badHeader], Array(repeating: OBDQueryResult(outcome: .failed), count: 4))
        let commands = transport.writtenCommands
        XCTAssertEqual(commands.count, 6)
    }

    /// 責務: 通信断で `connectionLost` となり、以後のすべての呼び出しも同じエラーになることを確認します。
    func testConnectionLostLatches() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: ["010C": [.failure]])
        let link = try await connect(transport)

        await assertConnectionLost { _ = try await link.query(self.rpm, header: nil) }
        await assertConnectionLost { _ = try await link.query(self.speed, header: nil) }
        await assertConnectionLost { _ = try await link.identify() }
        await assertConnectionLost { _ = try await link.supportedPIDs() }
        let commands = transport.writtenCommands
        XCTAssertEqual(commands.last, "010C", "切断後は何も送信しない")
    }

    /// 責務: closeの後の要求が `connectionLost` になり、Transportを1回だけ閉じることを確認します。
    func testCloseThenQueryThrows() async throws {
        let transport = DevicesScriptedOBDTransport()
        let link = try await connect(transport)
        await link.close()
        await link.close()

        await assertConnectionLost { _ = try await link.query(self.rpm, header: nil) }
        let closeCount = transport.closeCount
        XCTAssertEqual(closeCount, 1)
    }

    /// 責務: 対応ビットマップを00/20/40…と辿って対応PIDを集めることを確認します。
    func testSupportedPIDsWalksBitmaps() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: [
            "0100": [.response("41 00 80 18 00 01")],
            "0120": [.response("41 20 80 00 00 01")],
            "0140": [.response("41 40 40 00 00 00")]
        ])
        let link = try await connect(transport)

        let supported = try await link.supportedPIDs()

        let expected = [0x01, 0x0C, 0x0D, 0x21, 0x42].map { OBDPIDRequest(service: 0x01, pid: UInt8($0)) }
        XCTAssertEqual(supported, Set(expected))
    }

    /// 責務: 最初の範囲に応答が無い場合、空集合ではなく `timedOut` を投げることを確認します。
    func testSupportedPIDsThrowsWhenVehicleSilent() async throws {
        let transport = DevicesScriptedOBDTransport(scripts: ["0100": [.response("NO DATA")]])
        let link = try await connect(transport)
        do {
            _ = try await link.supportedPIDs()
            XCTFail("無応答が空集合として成功した")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .timedOut)
        }
    }

    private func assertConnectionLost(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("connectionLost にならなかった", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .connectionLost, file: file, line: line)
        }
    }
}
