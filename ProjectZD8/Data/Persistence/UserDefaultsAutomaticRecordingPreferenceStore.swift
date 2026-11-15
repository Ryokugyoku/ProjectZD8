import Foundation

/// `UserDefaults` を使って自動記録設定を端末ローカルに保持します(iCloudへは同期しません)。
@MainActor
final class UserDefaultsAutomaticRecordingPreferenceStore: AutomaticRecordingPreferencePort {
    /// 設定を保存する `UserDefaults` です。
    private let defaults: UserDefaults
    /// 設定を識別するキーです。
    private let key: String

    /// 保存先とキーを注入してストアを生成します。
    ///
    /// 責務: 自動記録設定の保存先を1件の `UserDefaults` キーへ固定します。
    /// - Parameters:
    ///   - defaults: 設定を保存する `UserDefaults`。
    ///   - key: 設定を識別するキー。
    init(
        defaults: UserDefaults = .standard,
        key: String = "deviceConnection.automaticRecordingEnabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// 自動記録設定を読み込みます。
    ///
    /// 責務: 保存済みの真偽値を返し、未保存または真偽値でない値は既定のオフとして扱います。
    /// - Returns: 自動記録が有効なら `true`。
    func load() -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    /// 自動記録設定を保存します。
    ///
    /// 責務: 1件の真偽値を置き換えて保存します。
    /// - Parameter isEnabled: 自動記録を有効にする場合は `true`。
    func save(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: key)
    }
}
