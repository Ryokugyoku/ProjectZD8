import SwiftUI
import WidgetKit

/// 記録中セッションのLive Activityの構成です。ロック画面とDynamic Islandの各表示へ部品を配置します。
struct RecordingSessionLiveActivityWidget: Widget {
    /// ロック画面の表示とDynamic Islandの各領域を `RecordingSessionActivityAttributes` に結び付けます。
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingSessionActivityAttributes.self) { context in
            RecordingSessionLiveActivityLockScreenView(state: context.state)
                .activitySystemActionForegroundColor(RecordingSessionLiveActivityPalette.accent)
        } dynamicIsland: { context in
            Self.dynamicIsland(state: context.state)
        }
    }

    /// Dynamic Islandの表示を組み立てます。
    ///
    /// 責務: expanded・compact・minimalの各領域へ部品を配置します。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: Dynamic Islandの構成。
    private static func dynamicIsland(state: RecordingSessionActivityAttributes.ContentState) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                RecordingSessionLiveActivityVehiclePhotoView(
                    fileName: state.vehiclePhotoFileName,
                    size: RecordingSessionLiveActivityMetrics.expandedPhotoSize
                )
            }
            DynamicIslandExpandedRegion(.trailing) {
                RecordingSessionLiveActivityElapsedTimerText(startedAt: state.startedAt)
                    .font(.headline)
            }
            DynamicIslandExpandedRegion(.center) {
                RecordingSessionLiveActivityTitleView(state: state)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: RecordingSessionLiveActivityMetrics.sectionSpacing) {
                    RecordingSessionLiveActivityMetricsRow(state: state)
                    RecordingSessionLiveActivityFooterView(receivedResponseCount: state.receivedResponseCount)
                }
            }
        } compactLeading: {
            RecordingSessionLiveActivityStatusIcon(tone: state.statusTone)
        } compactTrailing: {
            RecordingSessionLiveActivityMetricValueText(kind: .vehicleSpeed, metric: state.vehicleSpeed)
                .font(.caption.weight(.semibold))
        } minimal: {
            RecordingSessionLiveActivityStatusIcon(tone: state.statusTone)
        }
        .keylineTint(RecordingSessionLiveActivityPalette.accent)
    }
}
