#if os(iOS)
import AppIntents

/// 記録中のLive Activityの[切断]ボタンから、アプリを開かずに記録を終える操作です。アプリとWidget Extensionの両方に属します。
///
/// LiveActivityIntent のためアプリのプロセスで実行され、登録済みの停止処理(手動切断と同じ取得停止の要求)を呼びます。
/// 記録中でなければ何もせず成功を返します。
struct StopRecordingSessionIntent: LiveActivityIntent {
    /// ショートカット等に出る操作名です。
    static let title: LocalizedStringResource = "live_activity.action.stop"
    /// 操作の説明です。
    static let description = IntentDescription("live_activity.action.stop.description")
    /// Live Activityのボタン専用のため、ショートカットアプリ等には出しません。
    static let isDiscoverable = false

    /// 引数のない操作を生成します。
    ///
    /// 責務: App Intentsが要求する既定の生成を提供します。
    init() {}

    /// 記録の停止を要求します。
    ///
    /// 責務: 登録済みの停止処理へ[切断]操作を渡し、成功を返します。
    /// - Returns: 結果値のない成功。
    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingSessionStopIntentHandlerRegistry.performStop()
        return .result()
    }
}
#endif
