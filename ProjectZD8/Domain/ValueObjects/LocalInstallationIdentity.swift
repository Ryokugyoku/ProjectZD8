/// CloudKit受領証へ使用する現在アプリインストールの識別情報です。
struct LocalInstallationIdentity: Equatable, Sendable {
    /// 再起動後も維持する不透明なインストール識別子です。
    let id: String
    /// ユーザーが取込先を判別する端末表示名です。
    let displayName: String

    /// 不透明識別子と端末表示名を固定して生成します。
    ///
    /// 責務: 1件のアプリインストールを受領証向け識別情報へまとめます。
    /// - Parameters:
    ///   - id: 再起動後も維持する不透明識別子。
    ///   - displayName: ユーザー向け端末表示名。
    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
