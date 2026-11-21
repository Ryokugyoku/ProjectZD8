#if os(iOS)
import SwiftUI

/// iPhone の解析の「ルート」の表示で、地図の場所に出す読み込み中・描けない理由・失敗を表示します。
struct IOSSessionLogAnalysisRouteStatus: View {
    /// 地図の場所に出す内容です。地図を描ける内容では何も描きません。
    let content: RouteAnalysisSectionContent
    /// 再試行の要求を送出します。
    let onRetry: () -> Void

    /// 内容に応じた表示を描画します。
    ///
    /// 責務: 読み込み中は進捗と文言、描けない理由はアイコンと文言、
    /// 失敗は警告と文言と(再試行できる時だけ)再試行ボタンを、地図と同じ高さの枠の中央に描画します。
    var body: some View {
        Group {
            switch content {
            case .loading:
                loading
            case let .unavailable(reasonKey, systemImage):
                unavailable(reasonKey: reasonKey, systemImage: systemImage)
            case let .failed(messageKey, isRetryable):
                failed(messageKey: messageKey, isRetryable: isRetryable)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: IOSRouteAnalysisMetrics.statusMinHeight)
    }

    /// 読み込み中の表示です。
    ///
    /// 責務: 進捗の表示と読み込み中の文言を縦に並べます。
    private var loading: some View {
        VStack(spacing: IOSRouteAnalysisMetrics.statusSpacing) {
            ProgressView()
            Text("history.route.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 走行ルートを描けない理由の表示を作ります。
    ///
    /// 責務: 理由のアイコンと文言を中央に置きます。
    /// - Parameters:
    ///   - reasonKey: 理由のローカライズキー。
    ///   - systemImage: 添える SF Symbols の名前。
    /// - Returns: 理由の View。
    private func unavailable(reasonKey: String, systemImage: String) -> some View {
        VStack(spacing: IOSRouteAnalysisMetrics.statusSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: IOSRouteAnalysisMetrics.statusIconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(reasonKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 読み込みの失敗の表示を作ります。
    ///
    /// 責務: 赤の警告のアイコンと文言を中央に置き、再試行できる時だけ再試行ボタンを添えます。
    /// - Parameters:
    ///   - messageKey: 失敗の文言のローカライズキー。
    ///   - isRetryable: 再試行のボタンを出すか。
    /// - Returns: 失敗の View。
    private func failed(messageKey: String, isRetryable: Bool) -> some View {
        VStack(spacing: IOSRouteAnalysisMetrics.statusSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: IOSRouteAnalysisMetrics.statusIconSize))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(messageKey))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if isRetryable {
                Button("history.route.retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .accessibilityIdentifier("ios-analysis-route-retry")
            }
        }
    }
}
#endif
