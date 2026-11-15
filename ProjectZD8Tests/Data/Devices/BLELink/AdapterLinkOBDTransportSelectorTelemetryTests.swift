import XCTest
@testable import ProjectZD8

/// `AdapterLinkOBDTransportSelector.telemetryTransport(for:fallback:)` が、常駐リンクで始めた記録の取得では常駐リンクだけを使い、
/// 使えなければ自前の接続を開かずに失敗することを検証します(U2 受け入れ条件 6)。
@MainActor
final class AdapterLinkOBDTransportSelectorTelemetryTests: XCTestCase {
    /// 常駐リンクが保持するアダプターの識別子です。
    private static let linkedAdapter = UUID(uuidString: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")!
    /// 常駐リンクのアダプターの BLE 終端です。
    private static let endpoint = OBDConnectionEndpoint(
        transport: .bluetoothLowEnergy, systemIdentifier: linkedAdapter.uuidString, displayName: "OBDLink CX"
    )

    /// 選択を1回行った結果です。
    private struct Outcome {
        /// 選ばれたトランスポート。失敗した場合は `nil` です。
        let transport: (any OBDCommandTransport)?
        /// 投げられたエラーです。
        let error: (any Error)?
        /// 従来のトランスポート生成が呼ばれた回数です。
        let fallbackCalls: Int
        /// 従来のトランスポートとして用意した目印です。
        let fallback: FallbackOBDCommandTransportStub
    }

    /// 常駐リンクで始めた記録の取得中に、常駐リンクが `ready` でなければ `connectionLost` で失敗し、自前の接続を作りません。
    ///
    /// 責務: `ready` 以外の各状態で、エラーが `OBDPIDTelemetryError.connectionLost` で、従来生成が0回であることを確認します。
    func testRecordingOnUnreadyLinkFailsWithoutOwnConnection() {
        let states: [AdapterLinkState] = [.idle, .awaitingPeripheral, .connecting, .discovering, AdapterLinkByteStreamHarness.disconnected]
        for state in states {
            let outcome = select(linkState: state, isRecording: true)
            XCTAssertNil(outcome.transport, "\(state)")
            XCTAssertEqual(outcome.error as? OBDPIDTelemetryError, .connectionLost, "\(state)")
            XCTAssertEqual(outcome.fallbackCalls, 0, "\(state)")
        }
    }

    /// 常駐リンクで始めた記録の取得中でも、常駐リンクが同じアダプターを `ready` で保持していれば常駐リンクを使います。
    ///
    /// 責務: 常駐リンク上のトランスポートが返り、従来生成が呼ばれないことを確認します。
    func testRecordingOnReadyLinkUsesResidentLink() {
        let outcome = select(linkState: .ready, isRecording: true)
        XCTAssertTrue(outcome.transport is AdapterLinkOBDCommandTransport)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.fallbackCalls, 0)
    }

    /// 常駐リンクで始めた記録でなければ(手動接続など)、常駐リンクが `ready` でない時は従来どおり自前の接続です。
    ///
    /// 責務: 従来の目印が返り、従来生成が1回呼ばれることを確認します(U2「変えないもの」)。
    func testNotRecordingOnUnreadyLinkFallsBack() {
        let outcome = select(linkState: .connecting, isRecording: false)
        XCTAssertTrue((outcome.transport as AnyObject) === outcome.fallback)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.fallbackCalls, 1)
    }

    /// 取得用の選択器で1回選びます。
    ///
    /// 責務: リンク状態と記録中かどうかを固定した選択器で `telemetryTransport` を呼び、結果と従来生成の回数を返します。
    /// - Parameters:
    ///   - linkState: 常駐リンクの状態。
    ///   - isRecording: 常駐リンクで始めた記録の取得中かどうか。
    /// - Returns: 選択の結果。
    private func select(linkState: AdapterLinkState, isRecording: Bool) -> Outcome {
        let harness = AdapterLinkByteStreamHarness(state: linkState)
        let selector = AdapterLinkOBDTransportSelector(stream: harness.stream, linkTargetIdentifier: { Self.linkedAdapter })
        selector.isResidentLinkRecordingActive = { isRecording }
        let fallback = FallbackOBDCommandTransportStub()
        var calls = 0
        do {
            let transport = try selector.telemetryTransport(for: Self.endpoint) { _ in
                calls += 1
                return fallback
            }
            return Outcome(transport: transport, error: nil, fallbackCalls: calls, fallback: fallback)
        } catch {
            return Outcome(transport: nil, error: error, fallbackCalls: calls, fallback: fallback)
        }
    }
}
