import Foundation
@testable import ProjectZD8

/// LiveTelemetryModel を、要求を待たせるフェイク・手動時計・通知履歴と組み立てたテスト部品です。
@MainActor
final class LiveTelemetryModelFixture {
    /// 要求を記録して応答を待たせるPID取得境界です。
    let telemetry: GatedOBDPIDTelemetryFake
    /// 表示更新の間引きと要求の経過を測る手動時計です。
    let clock: ManualMonotonicClock
    /// 記録ポートのスパイです。記録しない経路では `nil` です。
    let recorder: LiveTelemetryRecordingPortSpy?
    /// スリープ抑止通知の記録です。
    let sleepInhibitor: VehicleConnectionSystemSleepInhibitorSpy
    /// Logging への通知の記録です。
    let notifications: LiveTelemetryModelNotificationLog
    /// 取得ループです。
    let loop: LiveTelemetryAcquisitionLoop
    /// 検証対象の表示モデルです。
    let model: LiveTelemetryModel

    /// PIDカタログと記録ポートを固定して生成します。
    ///
    /// 責務: 記録ポートがある場合は全PID収集有効のcapabilityを使い、無い場合はカタログ全体を使う表示モデルを組み立てます。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - failsCatalog: カタログ読込を失敗させる場合は `true`。
    ///   - recorder: 記録ポートのスパイ。
    init(catalog: [OBDPIDDefinition], failsCatalog: Bool = false, recorder: LiveTelemetryRecordingPortSpy? = nil) {
        let telemetry = GatedOBDPIDTelemetryFake()
        let clock = ManualMonotonicClock()
        let notifications = LiveTelemetryModelNotificationLog()
        let sleepInhibitor = VehicleConnectionSystemSleepInhibitorSpy()
        (self.telemetry, self.clock, self.notifications, self.sleepInhibitor, self.recorder) = (telemetry, clock, notifications, sleepInhibitor, recorder)
        let readMajorPIDs = ReadMajorOBDPIDsUseCase(
            definitionRepository: StubOBDPIDDefinitionRepository(definitions: catalog, failsRead: failsCatalog),
            telemetry: telemetry
        )
        let capabilities = recorder.map { _ in
            LoadVehiclePIDCapabilitiesUseCase(
                repository: StubVehiclePIDCapabilityRepository(
                    capabilities: catalog.map { StubVehiclePIDCapabilityRepository.capability($0, enabled: true) }
                ),
                telemetry: telemetry
            )
        }
        loop = LiveTelemetryAcquisitionLoop(telemetry: telemetry, recorder: recorder, clock: clock)
        model = LiveTelemetryModel(
            state: LiveTelemetryState(),
            prepareAcquisition: PrepareLiveTelemetryAcquisitionUseCase(readMajorPIDs: readMajorPIDs, loadVehicleCapabilities: capabilities),
            acquisitionLoop: loop,
            clock: clock,
            sessionDidEnd: { notifications.recordEnd($0) },
            distanceDidChange: { notifications.recordDistance($0) },
            systemSleepInhibitor: sleepInhibitor
        )
    }

    /// テスト車両で取得を始めます。
    ///
    /// 責務: 固定の終端・車両IDで開始操作を送ります。
    /// - Parameter vehicleModelCode: 型式コード。
    func start(vehicleModelCode: String? = nil) {
        model.send(.startRequested(LiveTelemetryTestDefinitions.endpoint, LiveTelemetryTestDefinitions.vehicleID, vehicleModelCode: vehicleModelCode))
    }

    /// 表示中のPIDごとの値です。
    var displayedValues: [OBDPIDRequest: Double] {
        Dictionary(model.state.samples.map { ($0.request, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// 状態が条件を満たすまで上限付きで待ちます。
    ///
    /// 責務: 表示状態の到達を待ち、上限を超えたら失敗させます。
    /// - Parameters:
    ///   - description: 失敗時に出す待機内容。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - condition: 待つ条件。
    /// - Returns: 到達した場合は `true`。
    @discardableResult
    func waitUntil(
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async -> Bool {
        await LiveTelemetryBoundedWaiter.waitUntil(description, file: file, line: line) { condition() }
    }

    /// 動いている取得を止めます。
    ///
    /// 責務: テスト終了時に応答待ちの要求を取消で解放し、取得Taskを残さないようにします。
    func tearDown() async {
        _ = await loop.stop()
    }
}
