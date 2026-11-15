import Foundation
import XCTest
@testable import ProjectZD8

/// `LiveTelemetryAction.startRequested` のアダプター判定結果が、取得ループを通って記録ポートの開始入力まで届くことと、
/// 再試行が直前の車両と判定結果で再開することを検証します。
@MainActor
final class LiveTelemetryModelAcquisitionStartInputTests: XCTestCase {
    /// チップ種別だけ(ATMA未試行)のアダプター判定結果です。
    private let chipOnly = AcquisitionAdapterProbeEvidence(chipFamily: .elm327Clone, monitorProbeOutcome: nil)
    /// ATMA判定ありのアダプター判定結果です。
    private let withATMA = AcquisitionAdapterProbeEvidence(chipFamily: .stn, monitorProbeOutcome: .framesReceived)
    /// 登録済み車両(型式なし)です。
    private let registered = LiveTelemetryVehicleContext.registered(LiveTelemetryTestDefinitions.vehicleID, vehicleModelCode: nil)
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

    /// 登録済み車両でチップ種別だけの判定結果を付けると、状態と開始入力の両方にその値が入ります。
    ///
    /// 責務: ATMA未試行の判定結果が欠落・補完なしで記録の開始入力へ届くことを確認します。
    func testRegisteredStartPassesChipOnlyProbe() async {
        let fixture = make()

        let input = await startAndCaptureInput(fixture, vehicle: registered, probe: chipOnly)

        XCTAssertEqual(input?.adapterProbeEvidence, chipOnly)
        XCTAssertEqual(fixture.model.state.adapterProbeEvidence, chipOnly)
    }

    /// 登録済み車両でATMA判定ありの結果を付けると、チップ種別とATMA結果の両方が開始入力へ入ります。
    ///
    /// 責務: 判定結果の2項目がどちらも落ちないことを確認します。
    func testRegisteredStartPassesProbeWithATMA() async {
        let input = await startAndCaptureInput(make(), vehicle: registered, probe: withATMA)

        XCTAssertEqual(input?.adapterProbeEvidence, withATMA)
    }

    /// 判定結果を付けない登録済み車両の開始では、状態と開始入力の判定結果は `nil` です。
    ///
    /// 責務: 判定なしを別の値で補完しないことを確認します。
    func testRegisteredStartWithoutProbePassesNil() async {
        let fixture = make()
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, registered))
        let arrived = await waitForStartInputs(1)

        XCTAssertTrue(arrived)
        XCTAssertNil(recorder.startInputs.first?.adapterProbeEvidence)
        XCTAssertNil(fixture.model.state.adapterProbeEvidence)
    }

    /// 未登録車両の開始でも、判定結果は対応PIDの探索を経て開始入力まで届きます。
    ///
    /// 責務: 常駐リンクで未登録車両を記録する経路で判定結果が欠落しないことを確認します。
    func testUnregisteredStartPassesProbe() async {
        let fixture = make()
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered, adapterProbeEvidence: withATMA))
        await releaseBitmap(fixture)
        let arrived = await waitForStartInputs(1)

        XCTAssertTrue(arrived)
        XCTAssertEqual(recorder.startInputs.first?.adapterProbeEvidence, withATMA)
        XCTAssertEqual(fixture.model.state.vehicle, .unregistered)
    }

    /// 判定結果を付けない未登録車両の開始では、開始入力の判定結果は `nil` です。
    ///
    /// 責務: 手動接続で未登録車両を記録する経路で判定結果を補完しないことを確認します。
    func testUnregisteredStartWithoutProbePassesNil() async {
        let fixture = make()
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered))
        await releaseBitmap(fixture)
        let arrived = await waitForStartInputs(1)

        XCTAssertTrue(arrived)
        XCTAssertNil(recorder.startInputs.first?.adapterProbeEvidence)
    }

    /// 判定結果ありで始めた後に判定結果なしで開始し直すと、2回目の開始入力は `nil` で、前回の値を引き継ぎません。
    ///
    /// 責務: 開始ごとに要求の判定結果で置き換わることを確認します。
    func testNewStartWithoutProbeDoesNotInheritPreviousProbe() async {
        let fixture = make()
        _ = await startAndCaptureInput(fixture, vehicle: registered, probe: withATMA)

        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, registered))
        let arrived = await waitForStartInputs(2)

        XCTAssertTrue(arrived)
        XCTAssertEqual(recorder.startInputs.map(\.adapterProbeEvidence), [withATMA, nil])
        XCTAssertNil(fixture.model.state.adapterProbeEvidence)
    }

    /// 再試行は直前の登録済み車両と判定結果で開始し直します。
    ///
    /// 責務: 再試行の開始入力の判定結果が直前と同じで、車両が変わらないことを確認します。
    func testRetryRestartsWithSameRegisteredVehicleAndProbe() async {
        let fixture = make()
        _ = await startAndCaptureInput(fixture, vehicle: registered, probe: chipOnly)

        fixture.model.send(.retryRequested)
        let arrived = await waitForStartInputs(2)

        XCTAssertTrue(arrived)
        XCTAssertEqual(recorder.startInputs.map(\.adapterProbeEvidence), [chipOnly, chipOnly])
        XCTAssertEqual(recorder.startInputs.map(\.generation), [1, 2])
        XCTAssertEqual(fixture.model.state.vehicle, registered)
    }

    /// 直前が未登録車両の開始なら、再試行も未登録車両として対応PIDを探索し直し、同じ判定結果で開始します。
    ///
    /// 責務: 再試行が車両ありへ取り違えず、ビットマップ照会からやり直すことを確認します。
    func testRetryAfterUnregisteredStartRestartsAsUnregistered() async {
        let fixture = make()
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, .unregistered, adapterProbeEvidence: withATMA))
        await releaseBitmap(fixture)
        _ = await waitForStartInputs(1)

        fixture.model.send(.retryRequested)
        let queried = await LiveTelemetryBoundedWaiter.waitUntil("再試行のビットマップ照会") {
            fixture.telemetry.sentRequests.filter { $0 == Self.bitmapRequest }.count == 2 && fixture.telemetry.pendingRequest == Self.bitmapRequest
        }
        await releaseBitmap(fixture)
        let arrived = await waitForStartInputs(2)

        XCTAssertTrue(queried)
        XCTAssertTrue(arrived)
        XCTAssertEqual(recorder.startInputs.map(\.adapterProbeEvidence), [withATMA, withATMA])
        XCTAssertEqual(fixture.model.state.vehicle, .unregistered)
    }

    /// 一度も開始していなければ、再試行は何も要求せず記録も始めません。
    ///
    /// 責務: 開始要求の無い再試行が状態・通信・記録を変えないことを確認します。
    func testRetryWithoutPriorStartDoesNothing() async {
        let fixture = make()

        fixture.model.send(.retryRequested)
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.model.state.phase, .idle)
        XCTAssertNil(fixture.model.state.vehicle)
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        XCTAssertEqual(recorder.calls, [])
    }

    // MARK: - Helpers

    /// 記録ポート付きのモデル部品を作り、後片付けの対象にします。
    ///
    /// 責務: 標準PID 0C/0D のカタログと記録ポートのスパイでモデル部品を返します。
    /// - Returns: モデル部品。
    private func make() -> LiveTelemetryModelFixture {
        recorder = LiveTelemetryRecordingPortSpy()
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]), recorder: recorder)
        self.fixture = fixture
        return fixture
    }

    /// 登録済み車両の取得を指定の判定結果で開始し、最初の開始入力を返します。
    ///
    /// 責務: 開始操作を送り、記録の開始入力が届くまで上限付きで待ちます。
    /// - Parameters:
    ///   - fixture: モデル部品。
    ///   - vehicle: 開始する車両。
    ///   - probe: 開始要求に付けるアダプター判定結果。
    /// - Returns: 最初の開始入力。上限内に届かなければ `nil`。
    private func startAndCaptureInput(
        _ fixture: LiveTelemetryModelFixture,
        vehicle: LiveTelemetryVehicleContext,
        probe: AcquisitionAdapterProbeEvidence
    ) async -> LiveTelemetryAcquisitionStartInput? {
        fixture.model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, vehicle, adapterProbeEvidence: probe))
        guard await waitForStartInputs(1) else { return nil }
        return recorder.startInputs.first
    }

    /// 未登録車両の対応PID探索へ、0C/0D に対応するビットマップを返します。
    ///
    /// 責務: 探索の照会1件へ継続なしのビットマップで応答します。
    /// - Parameter fixture: モデル部品。
    private func releaseBitmap(_ fixture: LiveTelemetryModelFixture) async {
        await fixture.telemetry.release(.responded(BitmapOBDPIDTelemetryFake.bitmap(supporting: [0x0C, 0x0D], base: 0x00, continues: false)))
    }

    /// 記録の開始入力が指定件数に達するまで上限付きで待ちます。
    ///
    /// 責務: 開始入力の到着を待ち、上限を超えたら失敗させます。
    /// - Parameter count: 待つ件数。
    /// - Returns: 到達した場合は `true`。
    private func waitForStartInputs(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        let recorder = recorder
        return await LiveTelemetryBoundedWaiter.waitUntil("開始入力 \(count) 件", file: file, line: line) {
            recorder.startInputs.count >= count
        }
    }
}
