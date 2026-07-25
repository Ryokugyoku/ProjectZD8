/// Appleアカウント単位で保持するConnection以外の設定値です。
struct AccountSettings: Codable, Equatable, Sendable {
    /// アプリ内表示に使用する言語です。
    var language: SettingsLanguage

    /// アプリ全体へ適用する外観です。
    var appearance: SettingsAppearance

    /// セッション終了時にRawログをiCloudへ自動送信するかを示します。
    var automaticSessionUploadEnabled: Bool

    /// アカウント設定を構成する値を指定して生成します。
    ///
    /// 責務: 同期対象である表示設定とセッション自動送信設定を1件のアカウント設定へまとめます。
    /// - Parameters:
    ///   - language: アプリ内表示に使用する言語。
    ///   - appearance: アプリ全体へ適用する外観。
    ///   - automaticSessionUploadEnabled: セッション終了時にiCloudへ自動送信する場合は `true`。
    init(
        language: SettingsLanguage = .japanese,
        appearance: SettingsAppearance = .system,
        automaticSessionUploadEnabled: Bool = false
    ) {
        self.language = language
        self.appearance = appearance
        self.automaticSessionUploadEnabled = automaticSessionUploadEnabled
    }
}

/// iOSとmacOSで共有するアプリ内表示言語です。
enum SettingsLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    /// 日本語表示を選択します。
    case japanese

    /// 英語表示を選択します。
    case english

    /// スペイン語表示を選択します。
    case spanish

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }
}

/// iOSとmacOSで共有するアプリ外観設定です。
enum SettingsAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    /// システムの外観設定へ追従します。
    case system

    /// 明るい外観を選択します。
    case light

    /// 暗い外観を選択します。
    case dark

    /// 選択状態とアクセシビリティ参照に使う安定識別子です。
    var id: String { rawValue }
}
