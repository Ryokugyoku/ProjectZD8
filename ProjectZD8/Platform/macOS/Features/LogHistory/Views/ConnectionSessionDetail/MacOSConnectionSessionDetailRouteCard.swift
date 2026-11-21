#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、走行ルートを全幅のカードとして表示します。
///
/// 地図を描ける時は左に操作できない地図、右に見出し・要約・注記・「地図を大きく表示」を並べます。
/// 描けない間は地図を出さず、見出しの下に取得中・理由・失敗の表示を置きます。
struct MacOSConnectionSessionDetailRouteCard: View {
    /// 走行ルートの読み込みの段階です。
    let phase: DrivingRouteDetailPhase
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// 地図を大きく表示する操作です。
    let onExpand: () -> Void
    /// 読み込みの再試行を送出します。
    let onRetry: () -> Void

    /// 段階に応じた中身をカードの枠に入れて描画します。
    ///
    /// 責務: 地図を描ける時は地図と右の列を、それ以外は見出しと状態の表示を、シアンの淡い枠に入れて描きます。
    var body: some View {
        Group {
            if case .loaded(let content) = phase {
                loadedContent(content)
            } else {
                VStack(alignment: .leading, spacing: MacOSDrivingRouteDetailMetrics.cardSpacing * scale) {
                    header
                    MacOSConnectionSessionDetailRouteStatus(phase: phase, scale: scale, onRetry: onRetry)
                }
            }
        }
        .padding(MacOSDrivingRouteDetailMetrics.cardPadding * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.06), in: cardShape)
        .overlay { cardShape.stroke(Color.cyan.opacity(0.18)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-history-route-card")
    }

    /// カードの枠の形です。
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacOSDrivingRouteDetailMetrics.cardCornerRadius * scale, style: .continuous)
    }

    /// 地図のアイコンと「走行ルート」の見出しです。
    private var header: some View {
        Label("history.route.title", systemImage: "map")
            .font(.system(size: MacOSDrivingRouteDetailMetrics.titleFontSize * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
    }

    /// 地図を描ける時の中身です。
    ///
    /// 責務: 左に幅可変・高さ固定の操作できない地図、右に固定幅の列を並べます。
    /// - Parameter content: 地図に描く内容。
    /// - Returns: 地図と右の列の View。
    private func loadedContent(_ content: DrivingRouteMapContent) -> some View {
        HStack(alignment: .top, spacing: MacOSDrivingRouteDetailMetrics.cardSpacing * scale) {
            RouteMapView(
                lines: content.geometry.polylines,
                markers: content.geometry.markers,
                bounds: content.geometry.bounds,
                focus: nil,
                interaction: .fixed,
                accessibilityLabelKey: "history.route.map.accessibility"
            )
            .frame(maxWidth: .infinity)
            .frame(height: MacOSDrivingRouteDetailMetrics.mapHeight * scale)
            .clipShape(RoundedRectangle(cornerRadius: MacOSDrivingRouteDetailMetrics.mapCornerRadius * scale, style: .continuous))
            sideColumn(content)
                .frame(width: MacOSDrivingRouteDetailMetrics.sideColumnWidth * scale, alignment: .leading)
                .frame(minHeight: MacOSDrivingRouteDetailMetrics.mapHeight * scale, alignment: .top)
        }
    }

    /// 地図の右に置く列です。
    ///
    /// 責務: 見出し・縦に並べた要約・注記を上から置き、「地図を大きく表示」を列の下端に置きます。
    /// - Parameter content: 地図に描く内容。
    /// - Returns: 右の列の View。
    private func sideColumn(_ content: DrivingRouteMapContent) -> some View {
        VStack(alignment: .leading, spacing: MacOSDrivingRouteDetailMetrics.sideColumnSpacing * scale) {
            header
            MacOSConnectionSessionDetailRouteSummary(summary: content.summary, scale: scale, isHorizontal: false)
            MacOSConnectionSessionDetailRouteNotices(noticeKeys: content.noticeKeys, scale: scale)
            Spacer(minLength: 0)
            Button(action: onExpand) {
                Label("history.route.expand", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityIdentifier("macos-history-route-expand")
        }
    }
}
#endif
