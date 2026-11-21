#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、走行ルートの地図を出せない間の表示(取得中・理由・失敗)を描きます。
///
/// 空の地図は出さず、段階ごとにアイコンと文言だけを描きます。
struct MacOSConnectionSessionDetailRouteStatus: View {
    /// 走行ルートの読み込みの段階です。`loaded` の時は何も描きません。
    let phase: DrivingRouteDetailPhase
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 読み込みの再試行を送出します。
    let onRetry: () -> Void

    /// 段階ごとの表示を描画します。
    ///
    /// 責務: 取得中は不確定の進捗、理由はアイコンと文言と注記、失敗は警告と文言と(再試行できる時だけ)再試行を描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSDrivingRouteDetailMetrics.statusSpacing * scale) {
            switch phase {
            case .idle, .waitingForAccount:
                ProgressView()
                    .controlSize(.small)
            case .loading:
                cloudLoading
            case .unavailable(let absence, let noticeKeys):
                message(absence.messageKey, systemImage: absence.systemImage, color: .secondary)
                MacOSConnectionSessionDetailRouteNotices(noticeKeys: noticeKeys, scale: scale)
            case .failed(let failure):
                message(failure.messageKey, systemImage: "exclamationmark.triangle.fill", color: .red)
                if failure.isRetryable {
                    Button("history.route.retry", action: onRetry)
                        .accessibilityIdentifier("macos-history-route-retry")
                }
            case .loaded:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: MacOSDrivingRouteDetailMetrics.statusMinHeight * scale, alignment: .leading)
    }

    /// iCloud から取得中であることを示す不確定の進捗です。
    private var cloudLoading: some View {
        HStack(spacing: MacOSDrivingRouteDetailMetrics.statusSpacing * scale) {
            ProgressView()
                .controlSize(.small)
            Label("history.route.loading.cloud", systemImage: "icloud.and.arrow.down")
                .font(.system(size: MacOSDrivingRouteDetailMetrics.statusMessageFontSize * scale))
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
        HStack(alignment: .top, spacing: MacOSDrivingRouteDetailMetrics.statusSpacing * scale) {
            Image(systemName: systemImage)
                .font(.system(size: MacOSDrivingRouteDetailMetrics.statusIconFontSize * scale, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(key))
                .font(.system(size: MacOSDrivingRouteDetailMetrics.statusMessageFontSize * scale))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
