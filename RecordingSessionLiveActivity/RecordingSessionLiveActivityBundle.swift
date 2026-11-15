import SwiftUI
import WidgetKit

/// 記録中セッションのLive Activityを提供するWidget Extensionの入口です。
@main
struct RecordingSessionLiveActivityBundle: WidgetBundle {
    /// Extensionが提供するウィジェットの一覧です。記録中表示のLive Activityだけを含みます。
    var body: some Widget {
        RecordingSessionLiveActivityWidget()
    }
}
