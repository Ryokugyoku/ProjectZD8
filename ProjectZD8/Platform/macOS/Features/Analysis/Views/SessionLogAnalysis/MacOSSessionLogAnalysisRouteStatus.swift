#if os(macOS)
import SwiftUI

/// macOS の解析の「ルート」の表示で、地図の場所に出す取得中・描けない理由・失敗を描きます。
///
/// 空の地図は出さず、内容ごとにアイコンと文言だけを描きます。
struct MacOSSessionLogAnalysisRouteStatus: View {
    /// 地図の場所に出す内容です。地図を描ける内容では何も描きません。
    let content: RouteAnalysisSectionContent
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 読み込みの再試行を送出します。
    let onRetry: () -> Void

    /// 内容ごとの表示を描画します。
    ///
    /// 責務: 表示前・サインイン待ちは小さな進捗、取得中は iCloud からの取得の不確定の進捗、
    /// 理由はアイコンと文言、失敗は警告と文言と(再試行できる時だけ)再試行を描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRouteAnalysisMetrics.statusSpacing * scale) {
            switch content {
            case .loading(let isLoadingRoute):
                if isLoadingRoute {
                    cloudLoading
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            case let .unavailable(reasonKey, systemImage):
                message(reasonKey, systemImage: systemImage, color: .secondary)
            case let .failed(messageKey, isRetryable):
                message(messageKey, systemImage: "exclamationmark.triangle.fill", color: .red)
                if isRetryable {
                    Button("history.route.retry", action: onRetry)
                        .accessibilityIdentifier("macos-analysis-route-retry")
                }
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: MacOSRouteAnalysisMetrics.statusMinHeight * scale, alignment: .leading)
    }

    /// iCloud から取得中であることを示す不確定の進捗です。
    private var cloudLoading: some View {
        HStack(spacing: MacOSRouteAnalysisMetrics.statusSpacing * scale) {
            ProgressView()
                .controlSize(.small)
            Label("history.route.loading.cloud", systemImage: "icloud.and.arrow.down")
                .font(.system(size: MacOSRouteAnalysisMetrics.statusMessageFontSize * scale))
                .foregroundStyle(.secondary)
        }
    }

    /// アイコンと文言を横に並べます。
    ///
    /// 責務: 理由・失敗の文言キーを `LocalizedStringKey` に包み、指定の色のアイコンを添えて描きます。
    /// - Parameters:
    ///   - key: 文言のローカライズキー。
    ///   - systemImage: SF Symbols の名前。
    ///   - color: アイコンの色。
    /// - Returns: アイコンと文言の View。
    private func message(_ key: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: MacOSRouteAnalysisMetrics.statusSpacing * scale) {
            Image(systemName: systemImage)
                .font(.system(size: MacOSRouteAnalysisMetrics.statusIconFontSize * scale, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(key))
                .font(.system(size: MacOSRouteAnalysisMetrics.statusMessageFontSize * scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
