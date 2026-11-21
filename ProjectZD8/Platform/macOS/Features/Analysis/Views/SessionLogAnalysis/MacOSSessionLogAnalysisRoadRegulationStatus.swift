#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードで、照合の結果が出ていない間の段階(待ち・照合中・照合できない理由・失敗)を描きます。
struct MacOSSessionLogAnalysisRoadRegulationStatus: View {
    /// 照合の段階です。`loaded` では何も描きません。
    let status: SessionRoadRegulationReviewStatus
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 照合の再試行を送出します。
    let onRetry: () -> Void
    /// 段階から文言キーと記号を引く表です。
    private let keys = SessionRoadRegulationReviewTextKeys()

    /// 段階ごとの表示を描画します。
    ///
    /// 責務: 記号のある段階はアイコンと文言、記号の無い段階(車速の読み込み待ち・照合中)は進捗と文言を描き、失敗の時だけ再試行を置きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
            if let messageKey = keys.statusMessageKey(for: status) {
                HStack(alignment: .top, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
                    indicator
                    Text(LocalizedStringKey(messageKey))
                        .font(.system(size: MacOSRoadRegulationReviewMetrics.statusMessageFontSize * metrics.scale))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if status == .failed {
                    Button("history.route.retry", action: onRetry)
                        .accessibilityIdentifier("macos-analysis-road-regulation-retry")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MacOSRoadRegulationReviewMetrics.statusMinHeight * metrics.scale, alignment: .leading)
    }

    /// 段階の記号、記号の無い段階では小さな進捗です。
    @ViewBuilder private var indicator: some View {
        if let systemImage = keys.statusSystemImage(for: status) {
            Image(systemName: systemImage)
                .font(.system(size: MacOSRoadRegulationReviewMetrics.statusIconFontSize * metrics.scale, weight: .semibold))
                .foregroundStyle(status == .failed ? Color.red : Color.secondary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}
#endif
