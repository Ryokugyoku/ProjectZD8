/// セッションへ記録する実行環境を提供する契約です。
nonisolated protocol AcquisitionEnvironmentPort: Sendable {
    /// 責務: 現在のアプリ版・端末種別・端末識別値を返します。
    func environment() -> AcquisitionEnvironment
}

/// セッション取得時の実行環境です。
nonisolated struct AcquisitionEnvironment: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let platform: AcquisitionPlatform
    /// インストール単位で安定な識別値です。
    let deviceID: String
    let deviceName: String

    /// 責務: 実行環境を生成します。
    init(appVersion: String, appBuild: String, platform: AcquisitionPlatform, deviceID: String, deviceName: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.platform = platform
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}
