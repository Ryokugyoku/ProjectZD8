import Foundation

/// 記録中セッションのLive Activityの属性です。アプリとWidget Extensionの両方に属します。
///
/// Extensionからも使うため、このファイルは他の製品型に依存しない自己完結の定義です(Foundationだけを使います)。
/// 表示内容の値型(`ContentState`、`VehicleLabel`、`Metric`、`StatusTone`)は同じく Foundation だけの別ファイルにあり、
/// macOS の単体テストからも検証できます。ActivityKit の `ActivityAttributes` への準拠だけを iOS 専用のファイルに置きます。
/// 表示内容はアプリ側でApplicationの純粋型 `RecordingSessionActivityContent` から `ContentState` へ写します。
/// 型名と入れ子の型名は ActivityKit の属性の識別と `ContentState` のエンコード形に関わるため変えません。
nonisolated struct RecordingSessionActivityAttributes: Codable, Hashable, Sendable {
    /// 車両写真を置くApp Group共有コンテナのIDです。
    static let appGroupIdentifier = "group.Ryokugyoku.ProjectZD8"
    /// 共有コンテナ内で車両写真を置くディレクトリ名です。
    static let vehiclePhotoDirectoryName = "SessionActivityVehiclePhotos"
    /// 「未登録の車両」を表す文言のローカライズキーです。
    static let unregisteredVehicleKey = "live_activity.vehicle.unregistered"
    /// 「未取得」を表す文言のローカライズキーです。
    static let unavailableMetricKey = "live_activity.metric.unavailable"
    /// 記録を終了した状態の文言のローカライズキーです。
    static let endedStatusKey = "live_activity.status.ended"
    /// 終了表示の「走行時間」見出しのローカライズキーです。
    static let drivingTimeLabelKey = "live_activity.ended.driving_time"
    /// 終了表示の「最大値」見出しのローカライズキーです。
    static let maximumsLabelKey = "live_activity.ended.maximums"
    /// [切断]ボタンの文言のローカライズキーです。
    static let stopButtonKey = "live_activity.action.stop"

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
