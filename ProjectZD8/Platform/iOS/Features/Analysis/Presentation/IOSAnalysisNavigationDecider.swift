#if os(iOS)
import WebKit

/// ワークベンチ以外への遷移(外部サイトや別スキーム)を拒否します。
struct IOSAnalysisNavigationDecider: WebPage.NavigationDeciding {
    /// 責務: アプリ独自スキームの同一ホストへの遷移だけを許可します。
    mutating func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url,
              url.scheme == ResolveAnalysisWebContentUseCase.scheme,
              url.host == ResolveAnalysisWebContentUseCase.host else { return .cancel }
        return .allow
    }
}
#endif
