import SwiftUI

/// 状態の強調に応じたアイコンです。通常はシアン、警告はオレンジで描きます。
struct RecordingSessionLiveActivityStatusIcon: View {
    /// 状態欄の強調です。
    let tone: RecordingSessionActivityAttributes.StatusTone

    /// 強調に対応するSF Symbolを強調色で描きます。
    var body: some View {
        Image(systemName: RecordingSessionLiveActivityStatusSymbol.name(for: tone))
            .foregroundStyle(RecordingSessionLiveActivityPalette.tint(for: tone))
    }
}
