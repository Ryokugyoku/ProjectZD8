#if os(iOS)
import Charts
import SwiftUI

/// iPhoneのセッション解析で代表PID組を近接時刻で対応付けた散布図を示すカードです。
struct IOSSessionLogAnalysisRelationshipCard: View {
    /// 選べるPID相関候補です。
    let relationships: [SessionPIDRelationship]
    /// 散布図へ表示するPID組の選択です。
    @Binding var selectedRelationshipID: String?
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 選択PID組の散布図、または相関候補が無い時の案内を表示します。
    ///
    /// 責務: 選択中または先頭のPID相関候補を、選択メニュー・読み方の案内・散布図のカードへ変換します。
    var body: some View {
        if let relationship = selectedRelationship {
            IOSSessionLogAnalysisCard(title: "analysis.relationship.title", subtitle: "analysis.relationship.subtitle") {
                Picker("analysis.relationship.pair", selection: $selectedRelationshipID) {
                    ForEach(relationships) { item in
                        Text(formatter.relationshipName(item)).tag(Optional(item.id))
                    }
                }
                relationshipGuide(relationship)
                if let modelCode = relationship.xSeries.vehicleModelCode ?? relationship.ySeries.vehicleModelCode {
                    VehicleModelBadge(modelCode: modelCode)
                }
                Chart(relationship.points) { point in
                    PointMark(
                        x: .value(formatter.seriesName(relationship.xSeries), point.x),
                        y: .value(formatter.seriesName(relationship.ySeries), point.y)
                    )
                    .foregroundStyle(Color.indigo.opacity(0.72))
                }
                .chartXAxisLabel(relationship.xSeries.unit)
                .chartYAxisLabel(relationship.ySeries.unit)
                .frame(height: 250)
            }
        } else {
            ContentUnavailableView(
                "analysis.relationship.empty.title",
                systemImage: "chart.dots.scatter",
                description: Text("analysis.relationship.empty.body")
            )
        }
    }

    /// 現在選択中または先頭の散布図系列です。
    private var selectedRelationship: SessionPIDRelationship? {
        relationships.first(where: { $0.id == selectedRelationshipID }) ?? relationships.first
    }

    /// 選択中の散布図について共通の読み方とPID組固有の観察目的を表示します。
    ///
    /// 責務: 1件のPID相関候補を誤診断を避ける利用解説へ変換します。
    /// - Parameter relationship: 解説対象のPID相関候補。
    /// - Returns: 散布点の読み方と選択組の観察目的を持つ案内表示。
    private func relationshipGuide(_ relationship: SessionPIDRelationship) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("analysis.relationship.guide.title", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("analysis.relationship.guide.common")
            Text(LocalizedStringKey(formatter.relationshipGuideKey(relationship)))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
