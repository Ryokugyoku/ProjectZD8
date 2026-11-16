import Foundation

/// `RecordingSessionActivityAttributes` の入れ子の値型 `ContentState` です。ActivityKit に依存せず、アプリ・Extension・macOS の単体テストで共有します。
extension RecordingSessionActivityAttributes {
    /// Live Activityの更新ごとに変わる表示内容です。
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// 車両名欄の内容です。
        var vehicle: VehicleLabel
        /// 状態を表すローカライズキーです。
        var statusKey: String
        /// 状態欄の強調です。
        var statusTone: StatusTone
        /// 車速(km/h)です。
        var vehicleSpeed: Metric
        /// エンジン回転数(rpm)です。
        var engineSpeed: Metric
        /// スロットル開度(%)です。
        var throttlePosition: Metric
        /// このセッションで受信した応答の件数です。
        var receivedResponseCount: Int
        /// 記録を開始した時刻です。経過時間の表示に使います。
        var startedAt: Date
        /// 共有コンテナの `vehiclePhotoDirectoryName` 内にある車両写真のファイル名です。無ければ `nil` です。
        var vehiclePhotoFileName: String?
        /// 記録終了後の表示に載せる走行時間と最大値です。記録中は `nil` で、値があれば終了表示です。
        var endedSummary: EndedSummary?

        /// 記録が終わった表示かどうかです。終了表示では[切断]とタイマーを出しません。
        var isEnded: Bool { endedSummary != nil }
    }
}
