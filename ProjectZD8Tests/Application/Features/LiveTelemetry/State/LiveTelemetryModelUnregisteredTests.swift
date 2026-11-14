import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両で開始した取得が、ECUが対応を返した標準PIDだけを要求し、未登録車両用の証跡で記録を始めることを検証します。
@MainActor
final class LiveTelemetryModelUnregisteredTests: XCTestCase {
    /// PIDカタログです(標準3件と車種専用2件)。
    private let catalog = LiveTelemetryTestDefinitions.standard([0x05, 0x0C, 0x0D]) + ZD8OBDPIDSeed.definitions
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 車両なしで開始すると、対応PIDを探索してから対応を返した標準PIDだけを要求し、車種専用PIDと対応外のPIDは一度も要求しません。
    ///
    /// 責務: 要求列・記録開始の定義とcapability・表示状態を、ループまで通して確認します。
    func testUnregisteredStartRequestsOnlySupportedStandardPIDs() async {
        let recorder = LiveTelemetryRecordingPortSpy()
        let fixture = make(recorder: recorder)
        fixture.start(vehicle: .unregistered)
        await fixture.telemetry.release(.responded(BitmapOBDPIDTelemetryFake.bitmap(supporting: [0x0C, 0x0D, 0x0F], base: 0x00, continues: false)))

        await fixture.telemetry.answer(4) { .responded([$0.pid]) }
        await fixture.telemetry.waitForSentRequests(6)

        let sent = fixture.telemetry.sentRequests
        XCTAssertEqual(sent.first, OBDPIDRequest(service: 0x01, pid: 0x00))
        XCTAssertEqual(Set(sent.dropFirst()), Set([0x0C, 0x0D].map(LiveTelemetryTestDefinitions.request)))
        XCTAssertFalse(sent.contains { $0.service != 0x01 })
        XCTAssertFalse(sent.contains(LiveTelemetryTestDefinitions.request(0x05)))
        let input = recorder.startInputs.first
        XCTAssertEqual(input?.definitions.map(LiveTelemetryTestDefinitions.request), [0x0C, 0x0D].map(LiveTelemetryTestDefinitions.request))
        XCTAssertEqual(input?.capabilities, [0x0C, 0x0D].map {
            ConnectionSessionAcquisitionPIDCapabilityInput.unregisteredVehicleSupported(LiveTelemetryTestDefinitions.request($0))
        })
        XCTAssertEqual(fixture.model.state.vehicle, .unregistered)
        XCTAssertEqual(fixture.model.state.phase, .loaded)
    }

    /// 対応PIDの探索に応答が無ければ、取得を始めずに無応答として終わります。
    ///
    /// 責務: 探索の失敗が空の取得や接続済み表示にならず、記録も始まらないことを確認します。
    func testDiscoveryWithoutResponseDoesNotStartAcquisition() async {
        let recorder = LiveTelemetryRecordingPortSpy()
        let fixture = make(recorder: recorder)
        fixture.start(vehicle: .unregistered)

        await fixture.telemetry.release(.timedOut)
        await fixture.waitUntil("無応答の終了") { fixture.model.state.failureKey != nil }

        XCTAssertEqual(fixture.model.state.phase, .idle)
        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.disconnected.no_response")
        XCTAssertEqual(fixture.notifications.endReasons, [.vehicleNoResponse])
        XCTAssertEqual(recorder.calls, [])
        XCTAssertEqual(fixture.telemetry.sentRequests, [OBDPIDRequest(service: 0x01, pid: 0x00)])
    }

    /// モデル部品を生成して後片付けの対象にします。
    ///
    /// 責務: 固定のカタログと記録ポートのスパイでモデル部品を返します。
    /// - Parameter recorder: 記録ポートのスパイ。
    /// - Returns: モデル部品。
    private func make(recorder: LiveTelemetryRecordingPortSpy) -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: catalog, recorder: recorder)
        self.fixture = fixture
        return fixture
    }
}
