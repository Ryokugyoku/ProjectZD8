/// 設定画面の「走行ルートを記録」区画に表示する内容です。
nonisolated struct RouteRecordingSettingsSection: Equatable, Sendable {
    /// 区画の種別を短く示すローカライズキーです。
    static let eyebrowKey = "settings.route_recording.eyebrow"
    /// 区画の見出しを表すローカライズキーです。
    static let titleKey = "settings.route_recording.title"
    /// 区画の目的を補足するローカライズキーです。
    static let descriptionKey = "settings.route_recording.description"
    /// 記録のオン・オフを切り替えるトグルのローカライズキーです。
    static let toggleKey = "settings.route_recording.toggle"
    /// 概略の位置しか許可されていないことを伝える注意のローカライズキーです。
    static let reducedAccuracyNoticeKey = "settings.route_recording.reduced_accuracy_notice"
    /// システムの設定アプリを開くリンクのローカライズキーです。
    static let openSystemSettingsKey = "settings.route_recording.open_system_settings"

    /// 保存済みの記録設定がオンなら `true`。
    let isEnabled: Bool
    /// 記録の状態です。
    let status: RouteRecordingSettingsStatus
    /// 設定がオンで許可もあるが、概略の位置しか許可されていない場合は `true`。
    let showsReducedAccuracyNotice: Bool

    /// 状態を警告として目立たせる場合は `true`(拒否・制限・使用中のみ・概略の位置のみ)。
    var isWarning: Bool {
        switch status {
        case .denied, .restricted, .foregroundOnly: true
        case .off, .awaitingPermission, .recordsInBackground, .unsupportedPlatform: showsReducedAccuracyNotice
        }
    }

    /// 設定アプリへのリンクを出す場合は `true`(拒否・使用中のみ・概略の位置のみ。制限では利用者が変えられないため出しません)。
    var showsSystemSettingsLink: Bool {
        switch status {
        case .denied, .foregroundOnly: true
        case .off, .awaitingPermission, .recordsInBackground, .restricted, .unsupportedPlatform: showsReducedAccuracyNotice
        }
    }

    /// 保存済みの設定と許可状態から区画内容を生成します。
    ///
    /// 責務: 設定値と許可状態を、表示する状態・注意の有無へ変換します。
    /// - Parameters:
    ///   - isEnabled: 保存済みの記録設定がオンなら `true`。
    ///   - permission: 現在の位置情報の許可状態。
    init(isEnabled: Bool, permission: LocationPermission) {
        self.isEnabled = isEnabled
        status = Self.status(isEnabled: isEnabled, level: permission.level)
        showsReducedAccuracyNotice = isEnabled
            && Self.grantsLocation(permission.level)
            && !permission.isPreciseAccuracy
    }

    /// 設定値と許可の段階から状態を決めます。
    ///
    /// 責務: 非対応のプラットフォームを最優先にし、オフ、許可の段階の順に状態へ変換します。
    /// - Parameters:
    ///   - isEnabled: 記録設定がオンなら `true`。
    ///   - level: 許可の段階。
    /// - Returns: 表示する状態。
    private static func status(isEnabled: Bool, level: LocationAuthorizationLevel) -> RouteRecordingSettingsStatus {
        if level == .unsupportedPlatform {
            return .unsupportedPlatform
        }
        guard isEnabled else { return .off }
        switch level {
        case .notDetermined: return .awaitingPermission
        case .denied: return .denied
        case .restricted: return .restricted
        case .whenInUse: return .foregroundOnly
        case .always: return .recordsInBackground
        case .unsupportedPlatform: return .unsupportedPlatform
        }
    }

    /// 許可の段階が位置の取得を認めているかを返します。
    ///
    /// 責務: 「使用中のみ」と「常に許可」だけを許可ありと判定します。
    /// - Parameter level: 許可の段階。
    /// - Returns: 位置の取得が許可されていれば `true`。
    private static func grantsLocation(_ level: LocationAuthorizationLevel) -> Bool {
        level == .whenInUse || level == .always
    }
}
