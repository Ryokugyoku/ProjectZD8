import SwiftUI
import WidgetKit

/// 記録中セッションのLive Activityの構成です。ロック画面とDynamic Islandの各表示へ部品を配置します。
struct RecordingSessionLiveActivityWidget: Widget {
    /// ロック画面の表示とDynamic Islandの各領域を `RecordingSessionActivityAttributes` に結び付けます。
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingSessionActivityAttributes.self) { context in
            Self.lockScreen(state: context.state)
                .activitySystemActionForegroundColor(RecordingSessionLiveActivityPalette.accent)
        } dynamicIsland: { context in
            Self.dynamicIsland(state: context.state)
        }
    }

    /// ロック画面の表示を選びます。
    ///
    /// 責務: 終了表示なら終了用の表示、記録中なら従来の表示を返します。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: ロック画面の表示。
    @ViewBuilder
    private static func lockScreen(state: RecordingSessionActivityAttributes.ContentState) -> some View {
        if let summary = state.endedSummary {
            RecordingSessionLiveActivityEndedView(state: state, summary: summary)
        } else {
            RecordingSessionLiveActivityLockScreenView(state: state)
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
                if let summary = state.endedSummary {
                    RecordingSessionLiveActivityEndedDurationText(seconds: summary.drivingSeconds)
                        .font(.headline)
                } else {
                    RecordingSessionLiveActivityElapsedTimerText(startedAt: state.startedAt)
                        .font(.headline)
                }
            }
            DynamicIslandExpandedRegion(.center) {
                if state.isEnded {
                    RecordingSessionLiveActivityEndedTitleView(state: state)
                } else {
                    RecordingSessionLiveActivityTitleView(state: state)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                expandedBottom(state: state)
            }
        } compactLeading: {
            RecordingSessionLiveActivityStatusIcon(tone: state.statusTone)
        } compactTrailing: {
            compactTrailing(state: state)
        } minimal: {
            RecordingSessionLiveActivityStatusIcon(tone: state.statusTone)
        }
        .keylineTint(RecordingSessionLiveActivityPalette.accent)
    }

    /// Dynamic Island(expanded)の下段を選びます。
    ///
    /// 責務: 終了表示なら最大値だけ(切断なし)、記録中なら計測値と[切断]付きのフッターを返します。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: 下段の表示。
    @ViewBuilder
    private static func expandedBottom(state: RecordingSessionActivityAttributes.ContentState) -> some View {
        if let summary = state.endedSummary {
            RecordingSessionLiveActivityEndedMaximumsRow(summary: summary)
        } else {
            VStack(spacing: RecordingSessionLiveActivityMetrics.sectionSpacing) {
                RecordingSessionLiveActivityMetricsRow(state: state)
                RecordingSessionLiveActivityFooterView(receivedResponseCount: state.receivedResponseCount)
            }
        }
    }

    /// Dynamic Island(compact)の右側を選びます。
    ///
    /// 責務: 終了表示なら固定の走行時間、記録中なら車速を返します。
    /// - Parameter state: Live Activityの最新の表示内容。
    /// - Returns: 右側の表示。
    @ViewBuilder
    private static func compactTrailing(state: RecordingSessionActivityAttributes.ContentState) -> some View {
        if let summary = state.endedSummary {
            RecordingSessionLiveActivityEndedDurationText(seconds: summary.drivingSeconds)
                .font(.caption.weight(.semibold))
        } else {
            RecordingSessionLiveActivityMetricValueText(kind: .vehicleSpeed, metric: state.vehicleSpeed)
                .font(.caption.weight(.semibold))
        }
    }
}
