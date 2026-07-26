/// 接続セッションを取得したAppleプラットフォームです。
nonisolated enum ConnectionSessionAcquisitionPlatform: String, Codable, Equatable, Sendable {
    /// iPhoneでログを取得しました。
    case iPhone
    /// iPadでログを取得しました。
    case iPad
    /// macOSでログを取得しました。
    case macOS
}

/// 接続セッションの取得元端末を示す不変スナップショットです。
nonisolated struct ConnectionSessionAcquisitionDevice: Codable, Equatable, Sendable {
    /// ログ取得時に動作していたAppleプラットフォームです。
    let platform: ConnectionSessionAcquisitionPlatform
    /// ログ取得時に取得できたユーザー向け端末名です。
    let name: String

    /// 取得プラットフォームと端末名を固定して生成します。
    ///
    /// 責務: 1件の取得元端末情報をセッション転送可能なスナップショットへまとめます。
    /// - Parameters:
    ///   - platform: ログ取得時に動作していたAppleプラットフォーム。
    ///   - name: ログ取得時に取得できたユーザー向け端末名。
    init(platform: ConnectionSessionAcquisitionPlatform, name: String) {
        self.platform = platform
        self.name = name
    }
}
