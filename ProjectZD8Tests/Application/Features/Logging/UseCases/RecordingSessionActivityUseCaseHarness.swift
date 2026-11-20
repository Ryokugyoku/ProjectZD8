import Foundation
import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` のテスト用に偽の境界・時刻・前面状態を束ねます。
@MainActor
final class RecordingSessionActivityUseCaseHarness {
    /// 常時表示の偽物です。
    let activity = SessionActivityPortSpy()
    /// 写真境界の偽物です。
    let photos = SessionActivityVehiclePhotoPortSpy()
    /// 診断の偽物です。
    let diagnostics = RecordingSessionActivityDiagnosticsSpy()
    /// 状態遷移の診断の偽物です。
    let lifecycleDiagnostics = RecordingSessionActivityLifecycleDiagnosticsSpy()
    /// 偽の現在時刻です。
    var currentDate = Date(timeIntervalSince1970: 1_000)
    /// 偽の前面状態です。
    var foreground = true
    /// 車両IDごとのプロフィールです。
    var profiles: [VehicleID: VehicleProfile] = [:]
    /// テスト対象です。
    private(set) var useCase: RecordingSessionActivityUseCase!

    /// 偽の境界でテスト対象を組み立てます。
    ///
    /// 責務: 時刻・前面状態・車両参照を、このハーネスの値へ結びます。
    init() {
        useCase = RecordingSessionActivityUseCase(
            activity: activity,
            photos: photos,
            diagnostics: diagnostics,
            now: { [unowned self] in currentDate },
            isForeground: { [unowned self] in foreground },
            vehicleProfile: { [unowned self] id in profiles[id] },
            lifecycleDiagnostics: lifecycleDiagnostics
        )
    }

    /// 取得状態を作ります。
    ///
    /// 責務: 段階・車速・車両から、テスト用の取得状態を1件作ります。
    func state(
        _ phase: LiveTelemetryState.Phase,
        speed: Double? = nil,
        vehicle: VehicleID? = nil
    ) -> LiveTelemetryState {
        var state = LiveTelemetryState()
        state.phase = phase
        if let speed {
            state.samples = [OBDPIDSample(
                request: RecordingSessionActivityContent.vehicleSpeedRequest,
                nameKey: "speed", value: speed, unit: "km/h", observedAt: currentDate
            )]
        }
        if let vehicle { state.vehicle = .registered(vehicle, vehicleModelCode: nil) }
        return state
    }

    /// 取得状態を渡し、境界操作の完了まで待ちます。
    ///
    /// 責務: 状態変化を渡し、受け付けた操作が終わってから戻ります。
    func send(_ state: LiveTelemetryState) async {
        useCase.telemetryStateDidChange(state)
        await waitForOperations()
    }

    /// 前面復帰を渡し、境界操作の完了まで待ちます。
    ///
    /// 責務: 前面復帰を渡し、受け付けた操作が終わってから戻ります。
    func enterForeground() async {
        useCase.appDidEnterForeground()
        await waitForOperations()
    }

    /// アプリの起動を渡し、境界操作の完了まで待ちます。
    ///
    /// 責務: 起動を渡し、受け付けた操作が終わってから戻ります。
    func launch() async {
        useCase.appDidLaunch()
        await waitForOperations()
    }

    /// 受け付けた境界操作の完了を、上限付きで待ちます。
    ///
    /// 責務: 操作が終わらない場合は待ち続けず、`XCTFail` で明示的に失敗させます。
    private func waitForOperations(file: StaticString = #filePath, line: UInt = #line) async {
        let useCase = useCase!
        _ = await LiveTelemetryBoundedWaiter.value(
            "境界操作の完了", file: file, line: line, of: { await useCase.waitForPendingOperations() }
        )
    }

    /// 写真付きの登録車両を作ります。
    ///
    /// 責務: プロフィールを登録し、その車両IDを返します。
    func registerVehicle(name: String = "BRZ", photo: Data? = Data([1, 2, 3])) -> VehicleID {
        let profile = VehicleProfile(vin: "JF1ZD8TEST", name: name, photoData: photo)
        profiles[profile.id] = profile
        return profile.id
    }
}
