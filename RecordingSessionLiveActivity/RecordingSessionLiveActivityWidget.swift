import SwiftUI
import WidgetKit

/// 記録中セッションのLive Activityの構成です。ロック画面とDynamic Islandの各表示へ部品を配置します。
///
/// どの表示で描くか(記録中・更新が止まった・終了)は `RecordingSessionLiveActivityDisplayMode` が決めます。
struct RecordingSessionLiveActivityWidget: Widget {
    /// ロック画面の表示とDynamic Islandの各領域を `RecordingSessionActivityAttributes` に結び付けます。
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingSessionActivityAttributes.self) { context in
            Self.lockScreen(state: context.state, mode: Self.mode(of: context))
                .activitySystemActionForegroundColor(RecordingSessionLiveActivityPalette.accent)
        } dynamicIsland: { context in
            Self.dynamicIsland(state: context.state, mode: Self.mode(of: context))
        }
    }

    /// 表示内容とシステムの判定から、どの表示で描くかを決めます。
    ///
    /// 責務: 終了表示かどうかと、有効期限を過ぎたかどうか(`isStale`)を表示の種類へ写します。
    /// - Parameter context: Live Activityの表示内容とシステムの状態。
    /// - Returns: 描く表示の種類。
    private static func mode(of context: ActivityViewContext<RecordingSessionActivityAttributes>) -> RecordingSessionLiveActivityDisplayMode {
        RecordingSessionLiveActivityDisplayMode(isEnded: context.state.isEnded, isStale: context.isStale)
    }

    /// ロック画面の表示を選びます。
    ///
    /// 責務: 終了表示なら終了用の表示、記録中(更新が止まった表示を含む)なら従来の表示を返します。
    /// - Parameters:
    ///   - state: Live Activityの最新の表示内容。
    ///   - mode: 描く表示の種類。
    /// - Returns: ロック画面の表示。
    @ViewBuilder
    private static func lockScreen(
        state: RecordingSessionActivityAttributes.ContentState,
        mode: RecordingSessionLiveActivityDisplayMode
    ) -> some View {
        if let summary = state.endedSummary {
            RecordingSessionLiveActivityEndedView(state: state, summary: summary)
        } else {
            RecordingSessionLiveActivityLockScreenView(state: state, mode: mode)
        }
    }

    /// Dynamic Islandの表示を組み立てます。
    ///
    /// 責務: expanded・compact・minimalの各領域へ部品を配置します。
    /// - Parameters:
    ///   - state: Live Activityの最新の表示内容。
    ///   - mode: 描く表示の種類。
    /// - Returns: Dynamic Islandの構成。
    private static func dynamicIsland(
        state: RecordingSessionActivityAttributes.ContentState,
        mode: RecordingSessionLiveActivityDisplayMode
    ) -> DynamicIsland {
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
                if mode == .ended {
                    RecordingSessionLiveActivityEndedTitleView(state: state)
                } else {
                    RecordingSessionLiveActivityTitleView(state: state, mode: mode)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                expandedBottom(state: state)
            }
        } compactLeading: {
            RecordingSessionLiveActivityStatusIcon(tone: mode.statusTone(for: state))
        } compactTrailing: {
            compactTrailing(state: state)
        } minimal: {
            RecordingSessionLiveActivityStatusIcon(tone: mode.statusTone(for: state))
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
