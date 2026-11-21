#if os(iOS)
import SwiftUI

/// iPhone の解析の「ルート」の表示で、色分けの指標をメニューで切り替え、選べない指標を案内します。
struct IOSSessionLogAnalysisRouteColorSourceMenu: View {
    /// 選択肢・選択・選べない案内です。
    let content: RouteAnalysisColorSourceMenuContent
    /// 色分けの元の選択を送出します。
    let onSelect: (RouteAnalysisColorSource) -> Void

    /// メニューと、選べない指標の案内を描画します。
    ///
    /// 責務: 選べない指標も disabled で並べたメニューを置き、その下に選べない理由と指標名を小さな文字で添えます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.legendSpacing) {
            Menu {
                ForEach(content.options) { option in
                    Button { onSelect(option.source) } label: { optionLabel(option) }
                        .disabled(!option.isEnabled)
                }
            } label: {
                menuLabel
            }
            .tint(.cyan)
            .accessibilityIdentifier("ios-analysis-route-color-source")
            if let reasonKey = content.unavailableReasonKey {
                unavailableNote(reasonKey: reasonKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// メニューの見出しです。
    ///
    /// 責務: 「色分けの指標」と、選んでいる指標の名前を横に並べます。
    private var menuLabel: some View {
        HStack(spacing: IOSRouteAnalysisMetrics.legendSpacing) {
            Text("analysis.route.color_source")
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let titleKey = content.selectedTitleKey {
                Text(LocalizedStringKey(titleKey))
                    .fontWeight(.semibold)
            }
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
    }

    /// メニューの1項目の見出しを作ります。
    ///
    /// 責務: 選んでいる項目だけ印を付けて名前を描きます。
    /// - Parameter option: 色分けの元の選択肢。
    /// - Returns: 項目の見出し。
    @ViewBuilder private func optionLabel(_ option: RouteAnalysisColorSourceOption) -> some View {
        if content.isSelected(option) {
            Label(LocalizedStringKey(option.titleKey), systemImage: "checkmark")
        } else {
            Text(LocalizedStringKey(option.titleKey))
        }
    }

    /// 選べない指標の案内を作ります。
    ///
    /// 責務: 選べない理由の文言の下に、選べない指標の名前を並べます。
    /// - Parameter reasonKey: 選べない理由のローカライズキー。
    /// - Returns: 案内の View。
    private func unavailableNote(reasonKey: String) -> some View {
        VStack(alignment: .leading, spacing: IOSRouteAnalysisMetrics.noticeSpacing) {
            Text(LocalizedStringKey(reasonKey))
            ForEach(content.unavailableTitleKeys, id: \.self) { titleKey in
                Label(LocalizedStringKey(titleKey), systemImage: "minus.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
