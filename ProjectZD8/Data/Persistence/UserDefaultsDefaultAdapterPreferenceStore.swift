import Foundation

/// `UserDefaults`を使ってデフォルトアダプター設定を保持します。
final class UserDefaultsDefaultAdapterPreferenceStore: DefaultAdapterPreferencePort {
    /// 保存辞書内で使用するフィールド名です。
    private enum Field {
        /// 安定識別子を保持するフィールド名です。
        static let adapterID = "adapterID"

        /// 接続方式を保持するフィールド名です。
        static let transportMode = "transportMode"

        /// 表示名を保持するフィールド名です。
        static let displayName = "displayName"

        /// システム識別子を保持するフィールド名です。
        static let systemIdentifier = "systemIdentifier"
    }

    /// 設定辞書を保存する`UserDefaults`です。
    private let defaults: UserDefaults

    /// 設定辞書を識別するキーです。
    private let key: String

    /// 保存先とキーを注入してストアを生成します。
    ///
    /// 責務: デフォルトアダプター設定の保存先を1件の`UserDefaults`キーへ固定します。
    /// - Parameters:
    ///   - defaults: 設定辞書を保存する`UserDefaults`。
    ///   - key: 設定辞書を識別するキー。
    init(
        defaults: UserDefaults = .standard,
        key: String = "deviceConnection.defaultAdapter"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// 現在保存されているデフォルトアダプター設定を読み込みます。
    ///
    /// 責務: 1件のプロパティリスト辞書を検証済みのデフォルト設定へ復元します。
    /// - Returns: 必須フィールドをすべて復元できた設定。不完全な場合は `nil`。
    func load() -> DefaultAdapterPreference? {
        guard
            let values = defaults.dictionary(forKey: key) as? [String: String],
            let adapterID = values[Field.adapterID],
            let rawTransportMode = values[Field.transportMode],
            let transportMode = AdapterTransportMode(rawValue: rawTransportMode),
            let displayName = values[Field.displayName],
            let systemIdentifier = values[Field.systemIdentifier]
        else {
            return nil
        }

        return DefaultAdapterPreference(
            adapterID: adapterID,
            transportMode: transportMode,
            displayName: displayName,
            systemIdentifier: systemIdentifier
        )
    }

    /// 指定されたデフォルトアダプター設定を保存します。
    ///
    /// 責務: 1件のデフォルト設定をプロパティリスト辞書として置き換えて保存します。
    /// - Parameter preference: 保存するデフォルトアダプターの識別情報。
    func save(_ preference: DefaultAdapterPreference) {
        defaults.set(
            [
                Field.adapterID: preference.adapterID,
                Field.transportMode: preference.transportMode.rawValue,
                Field.displayName: preference.displayName,
                Field.systemIdentifier: preference.systemIdentifier
            ],
            forKey: key
        )
    }

    /// 保存済みのデフォルトアダプター設定を削除します。
    ///
    /// 責務: 端末固有のデフォルトアダプター設定キーを存在しない状態へします。
    func remove() {
        defaults.removeObject(forKey: key)
    }
}
