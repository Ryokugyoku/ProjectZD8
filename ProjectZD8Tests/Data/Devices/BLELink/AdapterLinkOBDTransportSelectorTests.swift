import XCTest
@testable import ProjectZD8

/// `AdapterLinkOBDTransportSelector` が、常駐リンクが同じアダプターを `ready` で保持する時だけ常駐リンクを使うことを検証します。
@MainActor
final class AdapterLinkOBDTransportSelectorTests: XCTestCase {
    /// 常駐リンクが保持するアダプターの識別子です。
    private static let linkedAdapter = UUID(uuidString: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!

    /// 選択を1回行った結果です。
    private struct Selection {
        /// 選ばれたトランスポートです。
        let transport: any OBDCommandTransport
        /// 従来のトランスポート生成に渡された終端です(呼ばれた順)。
        let fallbackEndpoints: [OBDConnectionEndpoint]
        /// 従来のトランスポートとして用意した目印です。
        let fallback: FallbackOBDCommandTransportStub
    }

    /// 指定条件でトランスポートを選びます。
    ///
    /// 責務: リンク状態と保持アダプターを固定した選択器で1回選び、従来生成の呼び出しを記録して返します。
    /// - Parameters:
    ///   - endpoint: 接続しようとしている終端。
    ///   - linkState: 常駐リンクの状態。
    ///   - linkTarget: 常駐リンクが保持するアダプター。
    /// - Returns: 選択結果。
    private func select(
        _ endpoint: OBDConnectionEndpoint,
        linkState: AdapterLinkState = .ready,
        linkTarget: UUID? = AdapterLinkOBDTransportSelectorTests.linkedAdapter
    ) -> Selection {
        let harness = AdapterLinkByteStreamHarness(state: linkState)
        let selector = AdapterLinkOBDTransportSelector(stream: harness.stream, linkTargetIdentifier: { linkTarget })
        let fallback = FallbackOBDCommandTransportStub()
        var endpoints: [OBDConnectionEndpoint] = []
        let transport = selector.transport(for: endpoint) { requested in
            endpoints.append(requested)
            return fallback
        }
        return Selection(transport: transport, fallbackEndpoints: endpoints, fallback: fallback)
    }

    /// BLE 終端を作ります。
    ///
    /// 責務: 指定識別子の BLE 接続終端を返します。
    /// - Parameter identifier: 終端の識別子文字列。
    /// - Returns: BLE 接続終端。
    private static func bleEndpoint(_ identifier: String) -> OBDConnectionEndpoint {
        OBDConnectionEndpoint(transport: .bluetoothLowEnergy, systemIdentifier: identifier, displayName: "OBDLink CX")
    }

    /// 同じアダプターを `ready` で保持していれば、識別子の大文字小文字によらず常駐リンク上のトランスポートを返します。
    ///
    /// 責務: 大文字・小文字の識別子の両方で常駐リンク上のトランスポートが返り、従来生成が呼ばれないことを確認します。
    func testSameAdapterOnReadyLinkUsesResidentLink() {
        for identifier in [Self.linkedAdapter.uuidString.uppercased(), Self.linkedAdapter.uuidString.lowercased()] {
            let selection = select(Self.bleEndpoint(identifier))
            XCTAssertTrue(selection.transport is AdapterLinkOBDCommandTransport, identifier)
            XCTAssertTrue(selection.fallbackEndpoints.isEmpty, identifier)
        }
    }

    /// リンクが `ready` でなければ従来のトランスポートを返します。
    ///
    /// 責務: `ready` 以外の各状態で目印の stub が返り、従来生成へ終端が渡ることを確認します。
    func testLinkNotReadyFallsBack() {
        let states: [AdapterLinkState] = [.idle, .awaitingPeripheral, .connecting, .discovering, AdapterLinkByteStreamHarness.disconnected]
        let endpoint = Self.bleEndpoint(Self.linkedAdapter.uuidString)
        for state in states {
            assertFallback(select(endpoint, linkState: state), endpoint: endpoint, "\(state)")
        }
    }

    /// 保持アダプターが別、または無い場合は従来のトランスポートを返します。
    ///
    /// 責務: 別 UUID・保持なしの両方で目印の stub が返ることを確認します。
    func testDifferentOrMissingLinkTargetFallsBack() {
        let endpoint = Self.bleEndpoint(Self.linkedAdapter.uuidString)
        assertFallback(select(endpoint, linkTarget: UUID()), endpoint: endpoint, "別アダプター")
        assertFallback(select(endpoint, linkTarget: nil), endpoint: endpoint, "保持なし")
    }

    /// BLE でない終端は、識別子が同じでも従来のトランスポートを返します。
    ///
    /// 責務: Bluetooth Classic・シリアルの終端で目印の stub が返ることを確認します。
    func testNonBluetoothLowEnergyEndpointFallsBack() {
        for transport in [OBDConnectionEndpoint.Transport.bluetoothClassic, .serial] {
            let endpoint = OBDConnectionEndpoint(transport: transport, systemIdentifier: Self.linkedAdapter.uuidString, displayName: "Adapter")
            assertFallback(select(endpoint), endpoint: endpoint, "\(transport)")
        }
    }

    /// 従来のトランスポートが選ばれたことを確かめます。
    ///
    /// 責務: 返り値が目印の stub と同一で、従来生成へ同じ終端が1回だけ渡ったことを確認します。
    /// - Parameters:
    ///   - selection: 選択結果。
    ///   - endpoint: 渡した終端。
    ///   - message: 失敗時の補足。
    private func assertFallback(
        _ selection: Selection,
        endpoint: OBDConnectionEndpoint,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue((selection.transport as AnyObject) === selection.fallback, message, file: file, line: line)
        XCTAssertEqual(selection.fallbackEndpoints, [endpoint], message, file: file, line: line)
    }
}
