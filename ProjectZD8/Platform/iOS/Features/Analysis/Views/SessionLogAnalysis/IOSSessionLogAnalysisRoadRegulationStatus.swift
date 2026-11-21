#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」で、結果が出ていない間の段階(待ち・照合中・照合できない理由・失敗)を表示します。
struct IOSSessionLogAnalysisRoadRegulationStatus: View {
    /// 照合の段階です。`loaded` では何も描きません。
    let status: SessionRoadRegulationReviewStatus
    /// 再試行の要求を送出します。
    let onRetry: () -> Void
    /// 段階の文言キーと記号の表引きです。
    private let keys = SessionRoadRegulationReviewTextKeys()

    /// 段階に応じた表示を描画します。
    ///
    /// 責務: 文言キーがある段階だけ、記号が無ければ進捗、失敗なら赤の警告と再試行、それ以外は記号を文言に添えて中央に置きます。
    var body: some View {
        if let messageKey = keys.statusMessageKey(for: status) {
            VStack(spacing: IOSRoadRegulationReviewMetrics.statusSpacing) {
                indicator
                Text(LocalizedStringKey(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(status == .failed ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .failed {
                    Button("history.route.retry", action: onRetry)
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                        .accessibilityIdentifier("ios-analysis-road-regulation-retry")
                }
            }
            .frame(maxWidth: .infinity, minHeight: IOSRoadRegulationReviewMetrics.statusMinHeight)
        }
    }

    /// 段階の記号です。記号の無い段階(車速の読み込み待ち・照合中)は進捗の表示にします。
    ///
    /// 責務: 記号が無ければ `ProgressView`、失敗は赤、それ以外は控えめな色の記号を描きます。
    @ViewBuilder private var indicator: some View {
        if let systemImage = keys.statusSystemImage(for: status) {
            Image(systemName: systemImage)
                .font(.system(size: IOSRoadRegulationReviewMetrics.statusIconSize))
                .foregroundStyle(status == .failed ? Color.red : Color.secondary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
        }
    }
}
#endif
