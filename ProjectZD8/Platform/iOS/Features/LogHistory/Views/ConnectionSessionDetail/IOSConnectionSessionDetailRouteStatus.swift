#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細の走行ルートのカードで、地図を出さない段階(読み込み中・理由・失敗)を表示します。
struct IOSConnectionSessionDetailRouteStatus: View {
    /// 走行ルートの読み込みの段階です。地図を描ける段階では何も描きません。
    let phase: DrivingRouteDetailPhase
    /// 再試行の要求を送出します。
    let onRetry: () -> Void

    /// 段階に応じた表示を描画します。
    ///
    /// 責務: 表示前・アカウント待ち・読み込み中は読み込みの表示、描けない理由はアイコンと文言と注記、
    /// 失敗は警告と文言と(再試行できる時だけ)再試行ボタンを描画します。
    var body: some View {
        Group {
            switch phase {
            case .idle, .waitingForAccount, .loading:
                loading
            case .loaded:
                EmptyView()
            case let .unavailable(content, noticeKeys):
                unavailable(content, noticeKeys: noticeKeys)
            case let .failed(failure):
                failed(failure)
            }
        }
        .frame(maxWidth: .infinity, minHeight: IOSDrivingRouteDetailMetrics.statusMinHeight)
    }

    /// 読み込み中の表示です。
    ///
    /// 責務: 進捗の表示と読み込み中の文言を縦に並べます。
    private var loading: some View {
        VStack(spacing: IOSDrivingRouteDetailMetrics.statusSpacing) {
            ProgressView()
            Text("history.route.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// 走行ルートを描けない理由の表示を作ります。
    ///
    /// 責務: 理由のアイコンと文言を中央に置き、その下に注記を添えます。
    /// - Parameters:
    ///   - content: 理由の文言キーとアイコン。
    ///   - noticeKeys: 添える注記のローカライズキー。
    /// - Returns: 理由の View。
    private func unavailable(_ content: DrivingRouteUnavailableContent, noticeKeys: [String]) -> some View {
        VStack(spacing: IOSDrivingRouteDetailMetrics.statusSpacing) {
            Image(systemName: content.systemImage)
                .font(.system(size: IOSDrivingRouteDetailMetrics.statusIconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(content.messageKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            IOSConnectionSessionDetailRouteNotices(noticeKeys: noticeKeys)
        }
    }

    /// 読み込みの失敗の表示を作ります。
    ///
    /// 責務: 赤の警告のアイコンと文言を中央に置き、再試行できる時だけ再試行ボタンを添えます。
    /// - Parameter failure: 失敗の文言キーと再試行の可否。
    /// - Returns: 失敗の View。
    private func failed(_ failure: DrivingRouteFailure) -> some View {
        VStack(spacing: IOSDrivingRouteDetailMetrics.statusSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: IOSDrivingRouteDetailMetrics.statusIconSize))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(failure.messageKey))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if failure.isRetryable {
                Button("history.route.retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .accessibilityIdentifier("ios-history-route-card-retry")
            }
        }
    }
}
#endif
