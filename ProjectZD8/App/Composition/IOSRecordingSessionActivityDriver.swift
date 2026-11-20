#if os(iOS)
import Observation
import UIKit

/// PID継続取得の状態変化と前面復帰を、記録中の常時表示(Live Activity)のユースケースへ伝えます。
///
/// 表示の判断は `RecordingSessionActivityUseCase` に任せ、この型は状態の観測と事実の受け渡しだけを行います。
/// 状態は画面の表示を待たずに観測するため、バックグラウンドで始まった記録も次の前面復帰で表示できます。
@MainActor
final class IOSRecordingSessionActivityDriver {
    /// 記録中の常時表示を制御するユースケースです。
    private let useCase: RecordingSessionActivityUseCase
    /// 観測するPID継続取得のモデルです。
    private let liveTelemetry: LiveTelemetryModel

    /// ユースケースと観測元を固定して生成します。
    ///
    /// 責務: 事実の送り先と観測元を結び付けます。観測は `launch()` で始めます。
    /// - Parameters:
    ///   - useCase: 記録中の常時表示を制御するユースケース。
    ///   - liveTelemetry: 観測するPID継続取得のモデル。
    init(useCase: RecordingSessionActivityUseCase, liveTelemetry: LiveTelemetryModel) {
        self.useCase = useCase
        self.liveTelemetry = liveTelemetry
    }

    /// ActivityKit・App Group共有コンテナ・ローカル通知・統合ログの実装を注入した型を生成します。
    ///
    /// 責務: 常時表示のユースケースへ具象の境界・前面状態・車両プロフィールの参照先・背面開始の通知を結び付けます。
    /// - Parameters:
    ///   - liveTelemetry: 観測するPID継続取得のモデル。
    ///   - vehicleManagement: 車両名と写真を引く車両管理のモデル。
    /// - Returns: 観測が未開始の型。`launch()` で開始します。
    static func make(liveTelemetry: LiveTelemetryModel, vehicleManagement: VehicleManagementModel) -> IOSRecordingSessionActivityDriver {
        let lifecycleDiagnostics = OSLogRecordingSessionActivityLifecycleDiagnosticsAdapter()
        let useCase = RecordingSessionActivityUseCase(
            activity: ActivityKitRecordingSessionActivityAdapter(lifecycleDiagnostics: lifecycleDiagnostics),
            photos: AppGroupSessionActivityVehiclePhotoStore(),
            diagnostics: OSLogRecordingSessionActivityDiagnosticsAdapter(),
            isForeground: { UIApplication.shared.applicationState == .active },
            vehicleProfile: { id in vehicleManagement.state.vehicles.first { $0.id == id } },
            lifecycleDiagnostics: lifecycleDiagnostics
        )
        return IOSRecordingSessionActivityDriver(useCase: useCase, liveTelemetry: liveTelemetry)
    }

    /// 起動を伝えて状態の観測を始めます。アプリ起動時(BLEの状態復元による背面起動を含む)に1回だけ呼びます。
    ///
    /// 責務: 起動(前回のプロセスが残した表示の片付け)を先に伝え、現在の状態を伝えて以後の変化の観測を始めます。
    func launch() {
        useCase.appDidLaunch()
        observeTelemetryState()
    }

    /// アプリが前面へ戻ったこと(scenePhase が active)を伝えます。
    ///
    /// 責務: 前面復帰をユースケースの入力へ写します。
    func appDidBecomeActive() {
        useCase.appDidEnterForeground()
    }

    /// PID継続取得の状態を伝え、次の変化を1回だけ観測します。変化のたびに観測を登録し直します。
    ///
    /// 責務: 状態の読み取りを観測へ登録し、現在値をユースケースへ渡し、変化後にメインアクターで繰り返します。
    private func observeTelemetryState() {
        let state = withObservationTracking {
            liveTelemetry.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeTelemetryState() }
        }
        useCase.telemetryStateDidChange(state)
    }
}
#endif
