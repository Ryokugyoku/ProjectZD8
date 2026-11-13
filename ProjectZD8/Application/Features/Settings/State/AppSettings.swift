/// この端末に保存するアプリ設定です。端末間では同期しません。
nonisolated struct AppSettings: Equatable, Codable, Sendable {
    /// 外観(ライト・ダーク)の選択です。
    var appearance: AppAppearance
    /// デモモードです。有効な間だけ模擬アダプターが探索結果に現れ、取得したセッションはデモとして記録します。
    var isDemoModeEnabled: Bool
    /// iCloudへ保存済みのRawを、この端末に残しておく期間です。
    var localRawRetention: LocalRawRetention

    /// 責務: アプリ設定を生成します。
    init(appearance: AppAppearance = .system, isDemoModeEnabled: Bool = false, localRawRetention: LocalRawRetention) {
        self.appearance = appearance
        self.isDemoModeEnabled = isDemoModeEnabled
        self.localRawRetention = localRawRetention
    }
}

/// 外観の選択肢です。
nonisolated enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// iCloudへ保存済みのRawをこの端末に残す期間です。
nonisolated enum LocalRawRetention: String, Codable, CaseIterable, Sendable {
    case days30
    case days90
    case unlimited

    /// 保持日数です。無期限なら `nil` です。
    var days: Int? {
        switch self {
        case .days30: 30
        case .days90: 90
        case .unlimited: nil
        }
    }
}
