#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、走行ルートを操作できる地図として画面全体に表示します。
struct IOSConnectionSessionDetailRouteMapSheet: View {
    /// 地図に描く内容と要約です。
    let content: DrivingRouteMapContent
    /// 画面を閉じる要求を送出します。
    let onClose: () -> Void

    /// 操作できる地図の下端に要約を重ね、右上に閉じるボタンを置きます。
    ///
    /// 責務: 受け取った内容を移動・拡大縮小できる地図として描画し、閉じる操作を送出します。
    var body: some View {
        NavigationStack {
            RouteMapView(
                lines: content.geometry.polylines,
                markers: content.geometry.markers,
                bounds: content.geometry.bounds,
                focus: nil,
                interaction: .explorable,
                accessibilityLabelKey: "history.route.map.accessibility"
            )
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) { summaryOverlay }
            .navigationTitle("history.route.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("history.route.close", action: onClose)
                }
            }
        }
    }

    /// 地図の下端に重ねる要約です。
    ///
    /// 責務: 要約を半透明の素材の上に置き、画面の端から離します。
    private var summaryOverlay: some View {
        IOSConnectionSessionDetailRouteSummary(summary: content.summary)
            .padding(IOSDrivingRouteDetailMetrics.sheetSummaryPadding)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: IOSDrivingRouteDetailMetrics.sheetSummaryCornerRadius, style: .continuous)
            )
            .padding(IOSDrivingRouteDetailMetrics.sheetSummaryInset)
    }
}
#endif
