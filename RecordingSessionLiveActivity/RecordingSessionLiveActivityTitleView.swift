import SwiftUI

/// 車両名と状態文言を縦に並べた見出しです。更新が止まった表示では、状態文言を「更新が止まっています」に替えて注意の色で描きます。
struct RecordingSessionLiveActivityTitleView: View {
    /// Live Activityの最新の表示内容です。車両名と状態を読みます。
    let state: RecordingSessionActivityAttributes.ContentState
    /// 記録中の表示か、更新が止まった表示かです。
    let mode: RecordingSessionLiveActivityDisplayMode

    /// 車両名(未登録は既定の文言)と、状態アイコン付きの状態文言を描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: RecordingSessionLiveActivityMetrics.titleSpacing) {
            RecordingSessionLiveActivityVehicleNameText(vehicle: state.vehicle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: RecordingSessionLiveActivityMetrics.statusSpacing) {
                RecordingSessionLiveActivityStatusIcon(tone: mode.statusTone(for: state))
                Text(LocalizedStringKey(mode.statusKey(for: state)))
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(RecordingSessionLiveActivityPalette.tint(for: mode.statusTone(for: state)))
        }
    }
}
