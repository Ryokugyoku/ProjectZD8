#if os(macOS)
import SwiftUI

/// PID説明を見出しと4項目で示すポップオーバーの中身です。
struct MacOSLiveTelemetryPanelHelpPopover: View {
    /// 表示するPID説明の内容です。
    let content: LiveTelemetryPIDHelpContent

    /// PID名称と、概要・高値時・低値時・相関の4項目を縦に並べます。
    ///
    /// 責務: 1件のPID説明内容をポップオーバー用の縦並びへ描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(content.titleKey))
                .font(.headline)
            ForEach(content.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(row.titleKey))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey(row.bodyKey))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
#endif
