import XCTest
@testable import ProjectZD8

/// 通信経路の選択とエラー写像を検証します。
@MainActor
final class SystemOBDLinkPortTests: XCTestCase {
    /// 責務: `.demo` はTransportを作らずデモリンクを返すことを確認します。
    func testDemoAdapterReturnsDemoLinkWithoutTransport() async throws {
        let port = SystemOBDLinkPort(
            makeTransport: { _ in
                XCTFail("デモでTransportを作った")
                throw OBDTransportError.transportUnsupported
            },
            now: Date.init,
            makeDemoLink: { DemoOBDLink(latency: .zero) }
        )
        let link = try await port.open(DemoOBDLink.adapter)
        XCTAssertTrue(link is DemoOBDLink)
    }

    /// 責務: この端末で使えない経路が `transportUnsupported` になることを確認します。
    func testUnsupportedTransport() async {
        let port = SystemOBDLinkPort(
            makeTransport: { _ in throw OBDTransportError.transportUnsupported },
            now: Date.init,
            makeDemoLink: { DemoOBDLink(latency: .zero) }
        )
        let adapter = AdapterDescriptor(transport: .usbSerial, systemIdentifier: "/dev/cu.usbserial", displayName: "USB")
        do {
            _ = try await port.open(adapter)
            XCTFail("非対応が成功扱いになった")
        } catch {
            XCTAssertEqual(error as? OBDLinkError, .transportUnsupported)
        }
    }

    /// 責務: 実アダプターではTransportを開き、ELM327の初期化を終えたリンクを返すことを確認します。
    func testRealAdapterIsInitializedOverFactoryTransport() async throws {
        let transport = DevicesScriptedOBDTransport()
        let port = SystemOBDLinkPort(
            makeTransport: { _ in transport },
            now: Date.init,
            makeDemoLink: { DemoOBDLink(latency: .zero) }
        )
        let adapter = AdapterDescriptor(transport: .bluetoothLowEnergy, systemIdentifier: UUID().uuidString, displayName: "OBDLink")
        let link = try await port.open(adapter)
        XCTAssertTrue(link is ELM327OBDLink)
        let commands = transport.writtenCommands
        XCTAssertEqual(commands, ["ATZ", "ATE0", "ATL0", "ATS1", "ATH0", "ATSP0"])
    }
}
