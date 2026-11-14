/// アプリのルートが保持する、iOSとmacOSで共通のモデル一式です。
///
/// 各モデルは `ApplicationRootAssembly` が1回だけ生成し、モデル間の通知クロージャは同じインスタンスを捕捉します。
@MainActor
struct ApplicationRootModels {
    /// 認証セッションのモデルです。
    let authentication: AuthenticationSessionModel
    /// アカウント設定のモデルです。
    let accountSettings: AccountSettingsModel
    /// 車両管理のモデルです。
    let vehicleManagement: VehicleManagementModel
    /// 整備のモデルです。
    let maintenance: MaintenanceModel
    /// PID継続取得のモデルです。
    let liveTelemetry: LiveTelemetryModel
    /// 接続セッションのライフサイクルのモデルです。
    let connectionSessionLifecycle: ConnectionSessionLifecycleModel
    /// 接続履歴のモデルです。
    let connectionHistory: ConnectionHistoryModel
    /// 保存済みPIDログ解析のモデルです。
    let sessionLogAnalysis: SessionLogAnalysisModel
}
