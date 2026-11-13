/// 設定画面の選択肢1件です。
nonisolated struct SettingsOption<Value: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    /// 選択肢が表す値です。
    let value: Value
    /// 表示名のローカライズキーです。
    let nameKey: String

    /// `Identifiable` が使用する識別値です。
    var id: Value { value }
}
