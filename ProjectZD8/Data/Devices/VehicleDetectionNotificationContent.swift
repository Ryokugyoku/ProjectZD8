/// 車両検知の監視通知1件の内容です。通知センターに依存しない値で表します。
nonisolated struct VehicleDetectionNotificationContent: Equatable, Sendable {
    /// 通知の割り込みレベルです。
    enum InterruptionLevel: Equatable, Sendable {
        /// 通常の通知です。
        case active
        /// 集中モード中でも届く Time Sensitive 通知です。
        case timeSensitive
    }

    /// 置き換え式に提示するための固定の通知識別子です。
    let identifier: String
    /// 操作を付ける通知カテゴリの識別子です。操作の無い通知は `nil`。
    let categoryIdentifier: String?
    /// タイトルのローカライズキーです。
    let titleKey: String
    /// 本文のローカライズキーです。
    let bodyKey: String
    /// 本文の書式に埋め込む値です(VINなど)。
    let bodyArguments: [String]
    /// 割り込みレベルです。
    let interruptionLevel: InterruptionLevel
}
