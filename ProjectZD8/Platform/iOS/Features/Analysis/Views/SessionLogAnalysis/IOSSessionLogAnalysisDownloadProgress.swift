#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析でiCloud Rawログの取得率を示す進捗表示です。
struct IOSSessionLogAnalysisDownloadProgress: View {
    /// 0〜1の取得率です。
    let progress: Double

    /// iCloud Rawログの取得率をパーセントで表示します。
    ///
    /// 責務: 1件の取得率を線形の進捗バーと百分率の表示へ変換します。
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
            HStack {
                Label("analysis.download.progress", systemImage: "icloud.and.arrow.down")
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("ios-analysis-download-progress")
    }
}
#endif
