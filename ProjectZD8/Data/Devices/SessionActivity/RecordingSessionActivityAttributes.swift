#if os(iOS)
import ActivityKit
import Foundation

/// 記録中セッションのLive Activityの属性です。アプリとWidget Extensionの両方に属します。
///
/// Extensionからも使うため、このファイルは他の製品型に依存しない自己完結の定義です(ActivityKitとFoundationだけを使います)。
/// 表示内容はアプリ側でApplicationの純粋型 `RecordingSessionActivityContent` から `ContentState` へ写します。
nonisolated struct RecordingSessionActivityAttributes: ActivityAttributes {
    /// 車両写真を置くApp Group共有コンテナのIDです。
    static let appGroupIdentifier = "group.Ryokugyoku.ProjectZD8"
    /// 共有コンテナ内で車両写真を置くディレクトリ名です。
    static let vehiclePhotoDirectoryName = "SessionActivityVehiclePhotos"
    /// 「未登録の車両」を表す文言のローカライズキーです。
    static let unregisteredVehicleKey = "live_activity.vehicle.unregistered"
    /// 「未取得」を表す文言のローカライズキーです。
    static let unavailableMetricKey = "live_activity.metric.unavailable"
    /// [切断]ボタンの文言のローカライズキーです。
    static let stopButtonKey = "live_activity.action.stop"

    /// Live Activityの車両名欄の内容です。
    nonisolated enum VehicleLabel: Codable, Hashable, Sendable {
        /// 登録済み車両の名称です。
        case named(String)
        /// 未登録または名称不明の車両です。`unregisteredVehicleKey` の文言で描きます。
        case unregistered
    }

    /// Live Activityの1項目の計測値です。
    nonisolated enum Metric: Codable, Hashable, Sendable {
        /// 取得済みの数値です。
        case value(Double)
        /// 未取得です。`unavailableMetricKey` の文言で描きます。
        case unavailable
    }

    /// 状態欄の強調です。
    nonisolated enum StatusTone: Codable, Hashable, Sendable {
        /// 通常(シアン)です。
        case normal
        /// 警告(オレンジ)です。
        case warning
    }

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
    }

    /// 共有コンテナ内の車両写真ファイルのURLを返します。
    ///
    /// 責務: ファイル名をApp Group共有コンテナ内のURLへ変換します。
    /// - Parameter fileName: `ContentState.vehiclePhotoFileName` の値。
    /// - Returns: 写真ファイルのURL。共有コンテナが使えなければ `nil`。
    static func vehiclePhotoURL(fileName: String) -> URL? {
        vehiclePhotoDirectoryURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 共有コンテナ内の車両写真ディレクトリのURLを返します。
    ///
    /// 責務: App Group IDを写真ディレクトリのURLへ変換します。
    /// - Returns: ディレクトリのURL。共有コンテナが使えなければ `nil`。
    static func vehiclePhotoDirectoryURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(vehiclePhotoDirectoryName, isDirectory: true)
    }
}
#endif
