import SwiftUI

/// 終了表示の見出しです。車両名と「記録を終了しました」を並べ、終了の原因が警告なら原因を小さく添えます。
struct RecordingSessionLiveActivityEndedTitleView: View {
    /// Live Activityの最新の表示内容です。車両名と状態を読みます。
    let state: RecordingSessionActivityAttributes.ContentState

    /// 車両名、終了の文言、警告の原因(あれば)を縦に描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: RecordingSessionLiveActivityMetrics.titleSpacing) {
            RecordingSessionLiveActivityVehicleNameText(vehicle: state.vehicle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: RecordingSessionLiveActivityMetrics.statusSpacing) {
                Image(systemName: RecordingSessionLiveActivityStatusSymbol.name(for: .normal))
                Text(LocalizedStringKey(RecordingSessionActivityAttributes.endedStatusKey))
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(RecordingSessionLiveActivityPalette.accent)
            if state.statusTone == .warning {
                Text(LocalizedStringKey(state.statusKey))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(RecordingSessionLiveActivityPalette.warning)
            }
        }
    }
}
