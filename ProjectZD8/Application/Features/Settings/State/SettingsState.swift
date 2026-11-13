/// 設定画面が描画する状態です。
nonisolated struct SettingsState: Equatable, Sendable {
    /// 現在の設定です。
    var settings: AppSettings
    /// アプリのバージョンです(About表示用)。
    let appVersion: String
    /// アプリのビルド番号です(About表示用)。
    let appBuild: String

    /// 外観の選択肢です。
    static let appearanceOptions: [SettingsOption<AppAppearance>] = AppAppearance.allCases.map {
        SettingsOption(value: $0, nameKey: "settings.appearance.\($0.rawValue)")
    }
    /// Raw保持期間の選択肢です。
    static let retentionOptions: [SettingsOption<LocalRawRetention>] = LocalRawRetention.allCases.map {
        SettingsOption(value: $0, nameKey: "settings.retention.\($0.rawValue)")
    }

    /// "1.0 (42)" の形のバージョン表示です。
    var versionText: String { "\(appVersion) (\(appBuild))" }
}
