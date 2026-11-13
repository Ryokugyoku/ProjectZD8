import Foundation

/// 既定アダプターをUserDefaultsにJSONで保存します。
nonisolated struct UserDefaultsDefaultAdapterStore: DefaultAdapterStorePort {
    /// 保存に使うキーです。
    static let key = "insight.defaultAdapter"

    /// UserDefaultsはスレッドセーフなので、Sendableでない型でも安全に共有できます。
    private nonisolated(unsafe) let defaults: UserDefaults

    /// 責務: 保存先のUserDefaultsを指定してストアを生成します。
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 責務: 保存済みの既定アダプターを返します。未設定または復元できない場合は `nil` を返します。
    func load() -> AdapterDescriptor? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AdapterDescriptor.self, from: data)
    }

    /// 責務: 既定アダプターを保存します。`nil` で解除します。
    func save(_ adapter: AdapterDescriptor?) {
        guard let adapter else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(adapter), forKey: Self.key)
        } catch {
            assertionFailure("AdapterDescriptor は常にエンコードできる: \(error)")
        }
    }
}
