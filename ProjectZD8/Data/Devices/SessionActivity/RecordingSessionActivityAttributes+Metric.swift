import Foundation

/// `RecordingSessionActivityAttributes` の入れ子の値型 `Metric` です。ActivityKit に依存せず、アプリ・Extension・macOS の単体テストで共有します。
extension RecordingSessionActivityAttributes {
    /// Live Activityの1項目の計測値です。
    nonisolated enum Metric: Codable, Hashable, Sendable {
        /// 取得済みの数値です。
        case value(Double)
        /// 未取得です。`unavailableMetricKey` の文言で描きます。
        case unavailable
    }
}
