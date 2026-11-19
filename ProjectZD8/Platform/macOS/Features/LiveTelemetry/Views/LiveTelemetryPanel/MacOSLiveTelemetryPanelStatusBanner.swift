#if os(macOS)
import SwiftUI

/// リアルタイム表示パネルの取得状態を1行のバナーで示します。
struct MacOSLiveTelemetryPanelStatusBanner: View {
    /// 表示する状態バナーの内容です。
    let banner: LiveTelemetryStatusBanner
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 状態の文言、記号または進捗、トーンの色を横に並べます。
    ///
    /// 責務: 1件の状態バナーの内容を色付きの横長バナーへ描画します。
    var body: some View {
        let color = banner.tone.color
        let shape = RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
        HStack(spacing: 12 * scale) {
            if banner.showsProgress {
                ProgressView().controlSize(.small).tint(color)
            } else {
                Image(systemName: banner.symbol).foregroundStyle(color)
            }
            Text(LocalizedStringKey(banner.key))
                .font(.system(size: 12 * scale, weight: .semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16 * scale)
        .frame(minHeight: 46 * scale)
        .background(color.opacity(0.08), in: shape)
        .overlay { shape.stroke(color.opacity(0.18)) }
        .accessibilityElement(children: .combine)
    }
}
#endif
