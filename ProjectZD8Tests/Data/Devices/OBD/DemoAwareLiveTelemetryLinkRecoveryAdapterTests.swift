import Foundation
import XCTest
@testable import ProjectZD8

/// デモ終端では回復操作を何もせずに成功させ、それ以外は実アダプターへ渡すことを検証します。
@MainActor
final class DemoAwareLiveTelemetryLinkRecoveryAdapterTests: XCTestCase {
    /// デモ終端の3つの回復操作は、実アダプターを呼ばずに成功します。
    ///
    /// 責務: デモ終端で実アダプターの呼び出しが0件であることを確認します。
    func testDemoEndpointSucceedsWithoutLiveAdapter() async throws {
        let live = LinkRecoveryPortFake()
        let adapter = DemoAwareLiveTelemetryLinkRecoveryAdapter(live: live)
        let demo = OBDConnectionEndpoint(transport: .serial, systemIdentifier: DemoOBDAdapter.candidate.systemIdentifier, displayName: "DEMO")

        try await adapter.promptResync(using: demo)
        try await adapter.reinitializeFromReset(using: demo)
        try await adapter.reconnectLink(using: demo)

        XCTAssertEqual(live.calls, [])
    }

    /// デモ以外の終端では、3つの回復操作を実アダプターへ渡し、失敗もそのまま返します。
    ///
    /// 責務: 呼び出しの転送と、成功・失敗の伝播を確認します。
    func testRealEndpointForwardsToLiveAdapter() async throws {
        let live = LinkRecoveryPortFake()
        live.schedule([true, true, false])
        let adapter = DemoAwareLiveTelemetryLinkRecoveryAdapter(live: live)
        let real = OBDConnectionEndpoint(transport: .serial, systemIdentifier: "/dev/cu.real", displayName: "EX")

        try await adapter.promptResync(using: real)
        try await adapter.reinitializeFromReset(using: real)
        do {
            try await adapter.reconnectLink(using: real)
            XCTFail("実アダプターの失敗が成功になりました")
        } catch {
            XCTAssertEqual(error as? LiveTelemetryLinkRecoveryError, .rejected)
        }

        XCTAssertEqual(live.calls, [.promptResync, .reinitializeFromReset, .reconnectLink])
    }
}
