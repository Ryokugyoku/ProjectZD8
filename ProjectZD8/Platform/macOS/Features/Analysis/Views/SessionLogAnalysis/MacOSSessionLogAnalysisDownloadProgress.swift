#if os(macOS)
import SwiftUI

/// macOSのセッション解析でiCloud Rawログの取得率を示す進捗表示です。
struct MacOSSessionLogAnalysisDownloadProgress: View {
    /// 0〜1の取得率です。
    let progress: Double
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// iCloud Rawログの取得率をパーセントで表示します。
    ///
    /// 責務: 1件の取得率を線形の進捗バーと百分率の表示へ変換します。
    var body: some View {
        VStack(spacing: 12 * metrics.scale) {
            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
            HStack {
                Label("analysis.download.progress", systemImage: "icloud.and.arrow.down")
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.system(size: 13 * metrics.scale, weight: .semibold))
        }
        .padding(24 * metrics.scale)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
        .accessibilityIdentifier("macos-analysis-download-progress")
    }
}
#endif
