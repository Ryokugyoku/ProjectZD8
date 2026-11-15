import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両で始めた取得の準備が失敗した時(対応PIDが0件、カタログ読込の失敗)、`LiveTelemetryModel` が
/// 取得要求も記録も始めず、失敗状態と取得失敗の終了通知で終わることを検証します。
@MainActor
final class LiveTelemetryModelUnregisteredPreparationFailureTests: XCTestCase {
    /// 対応PID探索のビットマップ照会(Service 01 PID 00)です。
    private static let bitmapRequest = OBDPIDRequest(service: 0x01, pid: 0x00)
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?
    /// 各テストの記録ポートのスパイです。
    private var recorder = LiveTelemetryRecordingPortSpy()

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// ECUが対応を返したPIDが1件も無ければ、失敗状態になり、取得要求を1件も送らず記録も始めず、取得失敗で終了を1回通知します。
    ///
    /// 責務: 対応0件を空の取得や接続済み表示にせず、カタログ利用不能の失敗として終えることを確認します。
    func testNoSupportedPIDFailsWithoutRequestsOrRecording() async {
        let fixture = make(failsCatalog: false)
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered))

        await fixture.telemetry.release(.responded(BitmapOBDPIDTelemetryFake.bitmap(supporting: [], base: 0x00, continues: false)))
        await fixture.waitUntil("準備失敗の終了") { fixture.model.state.phase == .failed }

        assertPreparationFailed(fixture)
    }

    /// ECUが対応PIDを返しても、カタログを読めなければ同じ失敗状態で終わります。
    ///
    /// 責務: 未登録の経路のカタログ読込失敗が、取得の開始や空データにならないことを確認します。
    func testCatalogReadFailureFailsWithoutRequestsOrRecording() async {
        let fixture = make(failsCatalog: true)
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered))

        await fixture.telemetry.release(.responded(BitmapOBDPIDTelemetryFake.bitmap(supporting: [0x0C, 0x0D], base: 0x00, continues: false)))
        await fixture.waitUntil("準備失敗の終了") { fixture.model.state.phase == .failed }

        assertPreparationFailed(fixture)
    }

    // MARK: - Helpers

    /// 記録ポート付きのモデル部品を作り、後片付けの対象にします。
    ///
    /// 責務: 標準PID 0C/0D のカタログで、指定どおりカタログ読込を失敗させるモデル部品を返します。
    /// - Parameter failsCatalog: カタログ読込を失敗させる場合は `true`。
    /// - Returns: モデル部品。
    private func make(failsCatalog: Bool) -> LiveTelemetryModelFixture {
        recorder = LiveTelemetryRecordingPortSpy()
        let fixture = LiveTelemetryModelFixture(
            catalog: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]), failsCatalog: failsCatalog, recorder: recorder
        )
        self.fixture = fixture
        return fixture
    }

    /// 準備失敗の終わり方をまとめて確認します。
    ///
    /// 責務: 段階・失敗キー・表示値・送信要求・記録・終了通知・スリープ抑止を検証します。
    /// - Parameter fixture: モデル部品。
    private func assertPreparationFailed(_ fixture: LiveTelemetryModelFixture, file: StaticString = #filePath, line: UInt = #line) {
        let state = fixture.model.state
        XCTAssertEqual(state.phase, .failed, file: file, line: line)
        XCTAssertEqual(state.failureKey, "telemetry.error.pid_catalog_unavailable", file: file, line: line)
        XCTAssertFalse(state.isReceiving, file: file, line: line)
        XCTAssertEqual(state.samples, [], file: file, line: line)
        XCTAssertEqual(state.supportedPIDCount, 0, file: file, line: line)
        XCTAssertEqual(state.vehicle, .unregistered, file: file, line: line)
        XCTAssertEqual(fixture.telemetry.sentRequests, [Self.bitmapRequest], file: file, line: line)
        XCTAssertEqual(recorder.calls, [], file: file, line: line)
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed], file: file, line: line)
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false], file: file, line: line)
    }
}
