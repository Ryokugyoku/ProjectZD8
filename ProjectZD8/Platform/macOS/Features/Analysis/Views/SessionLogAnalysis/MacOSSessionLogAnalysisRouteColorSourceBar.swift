#if os(macOS)
import SwiftUI

/// macOS の解析の「ルート」の表示で、色分けの指標をチップの列で切り替えます。選べない指標は disabled にして理由を添えます。
struct MacOSSessionLogAnalysisRouteColorSourceBar: View {
    /// 選択肢・選択・選べない案内です。
    let content: RouteAnalysisColorSourceMenuContent
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 色分けの元の選択を送出します。
    let onSelect: (RouteAnalysisColorSource) -> Void

    /// 見出しとチップの列を描画します。
    ///
    /// 責務: 「色分けの指標」の見出しの横に、選択肢をチップとして並べます(はみ出す時は横に送れます)。
    var body: some View {
        HStack(spacing: MacOSRouteAnalysisMetrics.chipSpacing * scale) {
            Text("analysis.route.color_source")
                .font(.system(size: MacOSRouteAnalysisMetrics.chipFontSize * scale, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MacOSRouteAnalysisMetrics.chipSpacing * scale) {
                    ForEach(content.options) { option in
                        chip(option)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-analysis-route-color-source")
    }

    /// 選択肢1つのチップを作ります。
    ///
    /// 責務: 選んでいるチップはシアンで塗り、選べないチップは disabled にして理由を `help` に出します。
    /// - Parameter option: 色分けの元の選択肢。
    /// - Returns: チップの View。
    private func chip(_ option: RouteAnalysisColorSourceOption) -> some View {
        let isSelected = content.isSelected(option)
        return Button { onSelect(option.source) } label: {
            Text(LocalizedStringKey(option.titleKey))
                .font(.system(size: MacOSRouteAnalysisMetrics.chipFontSize * scale, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, MacOSRouteAnalysisMetrics.chipHorizontalPadding * scale)
                .frame(height: MacOSRouteAnalysisMetrics.chipHeight * scale)
                .background(isSelected ? Color.cyan : Color.primary.opacity(0.06), in: Capsule())
                .overlay { Capsule().stroke(Color.cyan.opacity(isSelected ? 0 : 0.25)) }
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .opacity(option.isEnabled ? 1 : 0.45)
        .help(helpText(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// チップに添える説明を作ります。
    ///
    /// 責務: 選べないチップには理由を、選べるチップには指標の名前を返します。
    /// - Parameter option: 色分けの元の選択肢。
    /// - Returns: 説明の文字。
    private func helpText(_ option: RouteAnalysisColorSourceOption) -> Text {
        Text(LocalizedStringKey(option.disabledReasonKey ?? option.titleKey))
    }
}
#endif
