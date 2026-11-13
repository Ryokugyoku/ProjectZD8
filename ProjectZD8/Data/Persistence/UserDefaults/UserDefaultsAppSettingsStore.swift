import Foundation

/// アプリ設定をUserDefaultsにJSONで保存します。
nonisolated struct UserDefaultsAppSettingsStore: AppSettingsStorePort {
    /// 保存に使うキーです。
    static let key = "insight.appSettings"

    /// UserDefaultsはスレッドセーフなので、Sendableでない型でも安全に共有できます。
    private nonisolated(unsafe) let defaults: UserDefaults
    private let defaultLocalRawRetention: LocalRawRetention

    /// 責務: 保存先と、未保存時に使うプラットフォーム既定のRaw保持期間を指定してストアを生成します。
    init(defaults: UserDefaults, defaultLocalRawRetention: LocalRawRetention) {
        self.defaults = defaults
        self.defaultLocalRawRetention = defaultLocalRawRetention
    }

    /// 責務: 保存済みの設定を返します。未保存または復元できない場合は既定値を返します。
    func load() -> AppSettings {
        if let data = defaults.data(forKey: Self.key), let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return AppSettings(localRawRetention: defaultLocalRawRetention)
    }

    /// 責務: 設定を保存します。
    func save(_ settings: AppSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            assertionFailure("AppSettings は常にエンコードできる: \(error)")
        }
    }
}
