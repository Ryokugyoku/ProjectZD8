@testable import ProjectZD8

/// 既定アダプター設定の保存境界の fake です。テストが保存値を差し替えます。
final class AdapterLinkSupervisionDefaultAdapterPreferenceStore: DefaultAdapterPreferencePort {
    /// 現在保存されている既定アダプター設定です。
    var preference: DefaultAdapterPreference?

    /// 読込回数です。
    private(set) var loadCount = 0

    /// 初期の保存値を指定して生成します。
    ///
    /// 責務: テスト開始時の既定アダプター設定を固定します。
    /// - Parameter preference: 初期の保存値。
    init(preference: DefaultAdapterPreference?) {
        self.preference = preference
    }

    /// 保存値を返します。
    ///
    /// 責務: 読込回数を数えて現在の保存値を返します。
    /// - Returns: 現在の保存値。
    func load() -> DefaultAdapterPreference? {
        loadCount += 1
        return preference
    }

    /// 保存値を置き換えます。
    ///
    /// 責務: 1件の設定を現在の保存値にします。
    /// - Parameter preference: 保存する設定。
    func save(_ preference: DefaultAdapterPreference) {
        self.preference = preference
    }
}
