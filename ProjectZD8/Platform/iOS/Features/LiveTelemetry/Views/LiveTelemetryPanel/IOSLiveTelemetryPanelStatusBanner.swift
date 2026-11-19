#if os(iOS)
import SwiftUI

/// リアルタイム表示パネルの取得状態を1行のバナーで示します。
struct IOSLiveTelemetryPanelStatusBanner: View {
    /// 表示する状態バナーの内容です。
    let banner: LiveTelemetryStatusBanner

    /// 状態の文言、記号または進捗、トーンの色を横に並べます。
    ///
    /// 責務: 1件の状態バナーの内容を色付きの横長バナーへ描画します。
    var body: some View {
        let color = banner.tone.color
        let shape = RoundedRectangle(cornerRadius: IOSLiveTelemetryPanelMetrics.bannerCornerRadius, style: .continuous)
        HStack(spacing: 12) {
            if banner.showsProgress {
                ProgressView().tint(color)
            } else {
                Image(systemName: banner.symbol).foregroundStyle(color)
            }
            Text(LocalizedStringKey(banner.key))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IOSLiveTelemetryPanelMetrics.bannerHorizontalPadding)
        .frame(minHeight: IOSLiveTelemetryPanelMetrics.bannerMinHeight)
        .background(color.opacity(IOSLiveTelemetryPanelMetrics.bannerFillOpacity), in: shape)
        .overlay { shape.stroke(color.opacity(IOSLiveTelemetryPanelMetrics.bannerStrokeOpacity)) }
        .accessibilityElement(children: .combine)
    }
}
#endif
