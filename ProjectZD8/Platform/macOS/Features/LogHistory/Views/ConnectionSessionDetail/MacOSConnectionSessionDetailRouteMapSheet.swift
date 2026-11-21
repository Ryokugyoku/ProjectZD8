#if os(macOS)
import SwiftUI

/// macOS のセッション詳細で、走行ルートの地図を大きく表示するシートです。地図は移動と拡大縮小ができます。
struct MacOSConnectionSessionDetailRouteMapSheet: View {
    /// 地図に描く内容(形・要約・注記)です。
    let content: DrivingRouteMapContent
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat
    /// シートを閉じる操作です。
    let onClose: () -> Void

    /// 見出し・操作できる地図・要約と注記の帯を縦に並べます。
    ///
    /// 責務: シートの寸法を `MacOSDrivingRouteDetailMetrics` に合わせ、閉じる操作を Esc キーにも割り当てます。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            RouteMapView(
                lines: content.geometry.polylines,
                markers: content.geometry.markers,
                bounds: content.geometry.bounds,
                focus: nil,
                interaction: .explorable,
                accessibilityLabelKey: "history.route.map.accessibility"
            )
            Divider()
            footer
        }
        .frame(
            width: MacOSDrivingRouteDetailMetrics.sheetWidth * scale,
            height: MacOSDrivingRouteDetailMetrics.sheetHeight * scale
        )
    }

    /// 題名と「閉じる」の帯です。
    private var header: some View {
        HStack {
            Label("history.route.title", systemImage: "map")
                .font(.system(size: MacOSDrivingRouteDetailMetrics.titleFontSize * scale, weight: .bold, design: .rounded))
            Spacer()
            Button("history.route.close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(MacOSDrivingRouteDetailMetrics.sheetBarPadding * scale)
    }

    /// 要約を横に並べ、注記を添えた下端の帯です。
    private var footer: some View {
        HStack(alignment: .top, spacing: MacOSDrivingRouteDetailMetrics.cardSpacing * scale) {
            MacOSConnectionSessionDetailRouteSummary(summary: content.summary, scale: scale, isHorizontal: true)
            Spacer(minLength: MacOSDrivingRouteDetailMetrics.cardSpacing * scale)
            MacOSConnectionSessionDetailRouteNotices(noticeKeys: content.noticeKeys, scale: scale)
                .frame(maxWidth: MacOSDrivingRouteDetailMetrics.sheetNoticeMaxWidth * scale, alignment: .leading)
        }
        .padding(MacOSDrivingRouteDetailMetrics.sheetBarPadding * scale)
    }
}
#endif
