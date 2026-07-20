import Foundation

/// UserDefaultsへアプリインストール識別子を保持します。
struct UserDefaultsInstallationIdentityStore {
    /// インストール識別子を保存するUserDefaultsキーです。
    private static let identifierKey = "installation.identity.v1"
    /// インストール識別子の保存先です。
    private let defaults: UserDefaults

    /// UserDefaults保存先を固定して生成します。
    ///
    /// 責務: 1件のUserDefaults領域をインストール識別子保存先へ結び付けます。
    /// - Parameter defaults: インストール識別子を保存するUserDefaults。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 保存済み識別子を復元し、未保存時だけ新規生成します。
    ///
    /// 責務: 現在インストールを安定識別子と指定端末名へ変換します。
    /// - Parameter displayName: ユーザーが端末を判別する表示名。
    /// - Returns: 再起動後も同じIDを使用するインストール識別情報。
    func identity(displayName: String) -> LocalInstallationIdentity {
        if let saved = defaults.string(forKey: Self.identifierKey), !saved.isEmpty {
            return LocalInstallationIdentity(id: saved, displayName: displayName)
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Self.identifierKey)
        return LocalInstallationIdentity(id: generated, displayName: displayName)
    }
}
