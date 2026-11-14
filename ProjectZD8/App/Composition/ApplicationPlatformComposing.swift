import Foundation

/// iOSとmacOSの組み立てが共通のルート組み立てへ提供する、OS固有の生成手順です。
///
/// `ApplicationRootAssembly` はこの手順だけを呼び、モデル間の配線をOSごとにコピーせず1か所で行います。
@MainActor
protocol ApplicationPlatformComposing {
    /// 取得区間を通知する匿名計測境界を生成します。
    ///
    /// 責務: OSの計測境界を1件生成します。
    /// - Returns: 取得区間を通知する匿名計測境界。
    static func makeAcquisitionPerformanceEventPort() -> any AcquisitionPerformanceEventPort

    /// 接続セッションの端末間同期を生成します。
    ///
    /// 責務: OSの同期経路を接続セッションの保存先へ結び付けます。
    /// - Parameter storage: 接続セッション・Rawログ・削除の保存先。
    /// - Returns: 接続セッションの同期ユースケース。
    static func makeConnectionSessionSynchronization(
        storage: any ConnectionSessionRepository & ConnectionSessionRawLogRepository & ConnectionSessionErasureRepository
    ) -> SynchronizeConnectionSessionsUseCase

    /// PID定義の保存先を生成します。
    ///
    /// 責務: 製品DB接続からPID定義の保存先を1件生成します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: PID定義の保存先。
    static func makeOBDPIDDefinitionRepository(database: ApplicationDatabaseConnection) -> any OBDPIDDefinitionRepository

    /// 新しいセッションへ固定する現在端末情報を生成します。
    ///
    /// 責務: OSの端末情報を1件生成します。
    /// - Returns: 現在端末情報。
    static func makeConnectionSessionAcquisitionDevice() -> ConnectionSessionAcquisitionDevice

    /// PID継続取得のモデルを生成します。
    ///
    /// 責務: OSのPID取得境界と共通の取得記録をLiveTelemetryモデルへ結び付けます。
    /// - Parameters:
    ///   - database: 製品DB接続。
    ///   - connectionSessionStorage: 接続session・取得証拠・チャンク・区間・欠損の保存先。
    ///   - activeSessionID: 現在Logging sessionの識別子を返す境界。
    ///   - performanceEvents: 取得区間を通知する匿名計測境界。
    ///   - sessionDidEnd: PID取得終了原因と終了時刻をLoggingへ通知する処理。
    ///   - distanceDidChange: 取得元付き累積距離をLoggingへ通知する処理。
    /// - Returns: PID継続取得のモデル。
    static func makeLiveTelemetryModel(
        database: ApplicationDatabaseConnection,
        connectionSessionStorage: ConnectionSessionStorageDependencies,
        activeSessionID: @escaping @Sendable () async -> ConnectionSessionID?,
        performanceEvents: any AcquisitionPerformanceEventPort,
        sessionDidEnd: @escaping @MainActor (ConnectionSessionEndReason, Date?) -> Void,
        distanceDidChange: @escaping @MainActor (ConnectionSessionDistanceObservation) -> Void
    ) -> LiveTelemetryModel

    /// 車両管理のモデルを生成します。
    ///
    /// 責務: OSの車両識別・同期境界を車両管理モデルへ結び付けます。
    /// - Parameters:
    ///   - database: 製品DB接続。
    ///   - connectionSessionRepository: 車両別ログ集計と車両削除に使う接続履歴の保存先。
    ///   - vehicleSessionsDidDelete: 車両関連セッション削除後に履歴表示へ再読込を通知する処理。
    ///   - connectionVehicleDidResolve: 登録済み車両の接続開始を通知する処理。
    ///   - unregisteredConnectionDidStart: 未登録車両の接続開始を通知する処理。
    ///   - unregisteredConnectionVehicleDidRegister: 車両なしの接続中に登録された車両を通知する処理。
    /// - Returns: 車両管理のモデル。
    static func makeVehicleManagementModel(
        database: ApplicationDatabaseConnection,
        connectionSessionRepository: any ConnectionSessionRepository & ConnectionSessionErasureRepository,
        vehicleSessionsDidDelete: @escaping @MainActor () -> Void,
        connectionVehicleDidResolve: @escaping @MainActor (VehicleProfile, OBDConnectionEndpoint, VehicleIdentificationSnapshot) -> Void,
        unregisteredConnectionDidStart: @escaping @MainActor (OBDConnectionEndpoint, VehicleIdentificationSnapshot) -> Void,
        unregisteredConnectionVehicleDidRegister: @escaping @MainActor (VehicleProfile) -> Void
    ) -> VehicleManagementModel

    /// 整備のモデルを生成します。
    ///
    /// 責務: OSの整備保存・同期を整備モデルへ結び付けます。
    /// - Parameter database: 製品DB接続。
    /// - Returns: 整備のモデル。
    static func makeMaintenanceModel(database: ApplicationDatabaseConnection) -> MaintenanceModel

    /// 認証セッションのモデルを生成します。
    ///
    /// 責務: OSのサインイン・資格復元・アカウント削除の境界を認証モデルへ結び付けます。
    /// - Parameters:
    ///   - database: 製品DB接続。
    ///   - connectionSessionStorage: アカウント削除時に接続セッションを消す保存先。
    /// - Returns: 認証セッションのモデル。
    static func makeAuthenticationSessionModel(
        database: ApplicationDatabaseConnection,
        connectionSessionStorage: any AccountConnectionSessionErasureRepository
    ) -> AuthenticationSessionModel

    /// アカウント設定のモデルを生成します。
    ///
    /// 責務: OSの設定保存・同期をアカウント設定モデルへ結び付けます。
    /// - Returns: アカウント設定のモデル。
    static func makeAccountSettingsModel() -> AccountSettingsModel
}
