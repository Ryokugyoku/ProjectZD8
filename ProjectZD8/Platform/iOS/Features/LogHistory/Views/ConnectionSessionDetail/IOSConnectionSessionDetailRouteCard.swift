#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、走行ルートを操作できない固定の地図と要約・注記のカードとして表示します。
struct IOSConnectionSessionDetailRouteCard: View {
    /// 走行ルートの読み込みの段階です。
    let phase: DrivingRouteDetailPhase
    /// 地図を大きく表示する要求を、表示する内容とともに送出します。
    let onExpand: (DrivingRouteMapContent) -> Void
    /// 再試行の要求を送出します。
    let onRetry: () -> Void

    /// 見出しと、段階に応じた中身をカードとして描画します。
    ///
    /// 責務: 地図を描ける段階では地図・要約・注記を、それ以外では状態の表示を、見出しの下に置きます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSDrivingRouteDetailMetrics.cardSpacing) {
            header
            if case let .loaded(content) = phase {
                loaded(content)
            } else {
                IOSConnectionSessionDetailRouteStatus(phase: phase, onRetry: onRetry)
            }
        }
        .padding(IOSDrivingRouteDetailMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: cardShape)
        .overlay { cardShape.stroke(Color.cyan.opacity(0.16)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-history-route-card")
    }

    /// カードの見出しです。
    ///
    /// 責務: 地図のアイコンと題名を置き、地図を描ける段階だけ右端に「地図を大きく表示」を置きます。
    private var header: some View {
        HStack(spacing: IOSDrivingRouteDetailMetrics.summarySpacing) {
            Label("history.route.title", systemImage: "map.fill")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
            if case let .loaded(content) = phase {
                Button { onExpand(content) } label: {
                    Label("history.route.expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .tint(.cyan)
                .accessibilityIdentifier("ios-history-route-card-expand")
            }
        }
    }

    /// 地図を描ける段階の中身を作ります。
    ///
    /// 責務: 操作できない地図・要約・注記を縦に並べます。
    /// - Parameter content: 地図に描く内容・要約・注記。
    /// - Returns: 中身の View。
    private func loaded(_ content: DrivingRouteMapContent) -> some View {
        VStack(alignment: .leading, spacing: IOSDrivingRouteDetailMetrics.cardSpacing) {
            RouteMapView(
                lines: content.geometry.polylines,
                markers: content.geometry.markers,
                bounds: content.geometry.bounds,
                focus: nil,
                interaction: .fixed,
                accessibilityLabelKey: "history.route.map.accessibility"
            )
            .frame(height: IOSDrivingRouteDetailMetrics.mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: IOSDrivingRouteDetailMetrics.mapCornerRadius, style: .continuous))
            IOSConnectionSessionDetailRouteSummary(summary: content.summary)
            IOSConnectionSessionDetailRouteNotices(noticeKeys: content.noticeKeys)
        }
    }

    /// カードの形です。
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IOSDrivingRouteDetailMetrics.cardCornerRadius, style: .continuous)
    }
}
#endif
