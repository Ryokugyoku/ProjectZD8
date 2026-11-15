import SwiftUI

/// 車両名と状態文言を縦に並べた見出しです。
struct RecordingSessionLiveActivityTitleView: View {
    /// Live Activityの最新の表示内容です。車両名と状態を読みます。
    let state: RecordingSessionActivityAttributes.ContentState

    /// 車両名(未登録は既定の文言)と、状態アイコン付きの状態文言を描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: RecordingSessionLiveActivityMetrics.titleSpacing) {
            RecordingSessionLiveActivityVehicleNameText(vehicle: state.vehicle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: RecordingSessionLiveActivityMetrics.statusSpacing) {
                RecordingSessionLiveActivityStatusIcon(tone: state.statusTone)
                Text(LocalizedStringKey(state.statusKey))
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(RecordingSessionLiveActivityPalette.tint(for: state.statusTone))
        }
    }
}
