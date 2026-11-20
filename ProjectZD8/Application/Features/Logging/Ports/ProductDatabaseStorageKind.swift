/// 製品DBを使う保存先の種類です。DB準備の失敗を診断へ残す時に、どの保存先を利用不能へ差し替えたかを表します。
nonisolated enum ProductDatabaseStorageKind: String, Equatable, Sendable, CaseIterable {
    /// 接続セッション・Rawログ・取得証跡・区間・欠損の保存先一式です。
    case connectionSessions
    /// PID変換定義の保存先です。
    case obdPIDDefinitions
    /// 車両別対応PIDの保存先です。
    case vehiclePIDCapabilities
    /// 整備記録の保存先です。
    case maintenanceRecords
    /// 接続セッションの位置サンプルと位置記録事象の保存先です。
    case connectionSessionLocations
    /// 走行ルートの同期記録の保存先です。
    case connectionSessionLocationTrackSync
}
