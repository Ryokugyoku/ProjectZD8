/// 走行ルート記録の配布役・保存役・ユースケース・設定モデル・配線型を、OSごとの部品から組み立てます。
///
/// iOS と macOS で同じ手順を使い、違いは `SessionLocationPlatformComponents` だけに閉じ込めます。
@MainActor
enum SessionLocationRecordingAssembly {
    /// 走行ルート記録の配線型と設定モデルを組み立てます。
    ///
    /// 責務: 位置の保存先と診断を1回ずつ生成し、保存済みの設定・現在の許可・前面かどうかを初期値にしたユースケースと、
    /// 設定の変更をそのユースケースへ伝える設定モデルを生成し、観測が未開始の配線型へ結び付けます。
    /// - Parameters:
    ///   - components: OSごとの許可・取得元・設定の保存先・前面判定。
    ///   - lifecycle: 現在の接続セッションを観測するライフサイクルのモデル。
    ///   - database: プロセス内で共有する製品DB接続。
    /// - Returns: `launch()` が未呼出しの配線型と、設定画面へ渡す設定モデル。
    static func make(
        components: SessionLocationPlatformComponents,
        lifecycle: ConnectionSessionLifecycleModel,
        database: ApplicationDatabaseConnection
    ) -> (driver: SessionLocationRecordingDriver, settings: RouteRecordingSettingsModel) {
        let repository = ProductDatabaseRepositoryFactory().makeConnectionSessionLocationRepository(database: database)
        let diagnostics = OSLogSessionLocationRecordingDiagnosticsAdapter()
        let preference = RouteRecordingPreferenceUseCase(preferencePort: components.preference)
        let useCase = SessionLocationRecordingUseCase(
            locations: LocationUpdateDistributor(source: components.source),
            recorder: ConnectionSessionLocationRecorder(repository: repository, diagnostics: diagnostics),
            repository: repository,
            diagnostics: diagnostics,
            isRecordingEnabled: preference.load(),
            permission: components.authorization.currentPermission,
            isForeground: components.isForeground()
        )
        let settings = RouteRecordingSettingsModel(
            preference: preference,
            authorization: components.authorization,
            preferenceDidChange: { useCase.recordingPreferenceDidChange(isEnabled: $0) }
        )
        let driver = SessionLocationRecordingDriver(
            useCase: useCase,
            lifecycle: lifecycle,
            authorization: components.authorization,
            settings: settings
        )
        return (driver, settings)
    }
}
