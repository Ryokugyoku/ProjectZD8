import Foundation

/// 時間の軸と色分けの方法から、解析の地図に描く内容(線・印・表示範囲・凡例)を作ります。モデルはこの型だけを呼びます。
///
/// - `.none`: すべて基本の色(`.base`)の線です。凡例はありません。
/// - `.metric`: 各点の時刻に最近傍で値を対応づけ、区分の番号(`.ramp`)か値なし(`.noValue`)に分けます。短い色の区間は併合します。
/// - `.overlay`: 重ね合わせの「連番の範囲 → 分類」で引き(外れた点は `.base`)、強調する時刻の範囲の線を後ろに足します。
/// - 印は最初の点に出発、2点以上ある時は最後の点に到着を置きます。表示範囲はすべての点を含む外接矩形です。
/// - 線の点の合計は `pointBudget` 以下です。強調の線がある時は、その点数(上限の半分まで)を先に取り分けます。
nonisolated struct RouteAnalysisMapLayerBuilder: Sendable {
    /// 点ごとの分類と、線の作り方の組です。
    private typealias ColoringPlan = (
        categories: [RouteAnalysisColorCategory],
        mergesShortRuns: Bool,
        hasMatchedValues: Bool,
        highlightedTimeRanges: [ClosedRange<Date>]
    )

    /// 出発の印の番号です。
    private static let startMarkerID = 0
    /// 到着の印の番号です。
    private static let endMarkerID = 1

    /// 色の区間の線を作る部品です。
    private let painter: RouteAnalysisLinePainter
    /// 点の時刻に値を対応づける部品です。
    private let matcher: RouteAnalysisValueMatcher
    /// 指標の凡例を作る部品です。
    private let legendBuilder: RouteAnalysisLegendBuilder
    /// 強調の線を作る部品です。
    private let highlightBuilder: RouteAnalysisHighlightBuilder
    /// 強調の線の間引きです。
    private let highlightSimplifier = GeoPolylineSimplifier()
    /// 線の点の合計の上限です。
    private let pointBudget: Int

    /// 部品と点数の上限を固定して作ります。
    ///
    /// 責務: 地図の内容を作る部品と、線の点の合計の上限を保持します。
    /// - Parameters:
    ///   - painter: 色の区間の線を作る部品。
    ///   - matcher: 点の時刻に値を対応づける部品。
    ///   - legendBuilder: 指標の凡例を作る部品。
    ///   - highlightBuilder: 強調の線を作る部品。
    ///   - pointBudget: 線の点の合計の上限(既定は 5,000)。
    init(
        painter: RouteAnalysisLinePainter = .init(),
        matcher: RouteAnalysisValueMatcher = .init(),
        legendBuilder: RouteAnalysisLegendBuilder = .init(),
        highlightBuilder: RouteAnalysisHighlightBuilder = .init(),
        pointBudget: Int = 5_000
    ) {
        self.painter = painter
        self.matcher = matcher
        self.legendBuilder = legendBuilder
        self.highlightBuilder = highlightBuilder
        self.pointBudget = pointBudget
    }

    /// 地図に描く内容を作ります。
    ///
    /// 責務: 色分けの方法から点ごとの分類を決め、色の区間の線と強調の線を点数の上限の中で作り、印・範囲・凡例をそろえます。
    /// - Parameters:
    ///   - timeline: 時刻の昇順の点列。
    ///   - coloring: 色分けの方法。
    /// - Returns: 地図に描く内容。点が無ければ線・印は空、範囲は `nil` です。
    func layers(timeline: RouteAnalysisTimeline, coloring: RouteAnalysisColoring) -> RouteAnalysisMapLayers {
        let points = timeline.points
        let plan = coloringPlan(for: coloring, timeline: timeline)
        let budget = max(pointBudget, 0)
        let rawHighlights = highlightBuilder.lines(timeline: timeline, ranges: plan.highlightedTimeRanges, firstID: 0)
        let reserved = min(rawHighlights.reduce(0) { $0 + $1.coordinates.count }, budget / 2)
        let colorLines = painter.lines(
            timeline: timeline,
            categories: plan.categories,
            mergesShortRuns: plan.mergesShortRuns,
            pointBudget: budget - reserved
        )
        let hasNoValueEdges = colorLines.contains { $0.category == .noValue }
        return RouteAnalysisMapLayers(
            lines: colorLines + simplifiedHighlights(rawHighlights, pointBudget: reserved, firstID: colorLines.count),
            markers: Self.markers(of: points),
            bounds: GeoBoundingBox(enclosing: points.map(\.coordinate)),
            legend: legend(for: coloring, includesNoValue: hasNoValueEdges),
            hasNoValueEdges: hasNoValueEdges,
            hasMatchedValues: plan.hasMatchedValues
        )
    }

    /// 色分けの方法ごとに、点の分類と線の作り方を決めます。
    ///
    /// 責務: `.none` は基本の色、`.metric` は値の区分、`.overlay` は連番の範囲で分類し、併合の有無・値の対応・強調の範囲を添えます。
    /// - Parameters:
    ///   - coloring: 色分けの方法。
    ///   - timeline: 時刻の昇順の点列。
    /// - Returns: 点ごとの分類と線の作り方。
    private func coloringPlan(for coloring: RouteAnalysisColoring, timeline: RouteAnalysisTimeline) -> ColoringPlan {
        switch coloring {
        case .none:
            return ([RouteAnalysisColorCategory](repeating: .base, count: timeline.points.count), false, false, [])
        case let .metric(metric, series):
            let categories = metricCategories(timeline: timeline, bands: metric.bands, series: series)
            return (categories, true, categories.contains { $0 != .noValue }, [])
        case let .overlay(overlay):
            let categories = painter.categories(timeline: timeline, runs: overlay.runs, fallback: .base)
            let probe = painter.categories(timeline: timeline, runs: overlay.runs, fallback: .noValue)
            let hasCoveredPoint = zip(categories, probe).contains { $0 == $1 }
            return (categories, false, hasCoveredPoint, overlay.highlightedTimeRanges)
        }
    }

    /// 各点の時刻に値を対応づけ、値の区分で分類します。
    ///
    /// 責務: 許容差の中で最も近い値の区分の番号を `.ramp` にし、値が無い・有限でない点は `.noValue` にします。
    /// - Parameters:
    ///   - timeline: 時刻の昇順の点列。
    ///   - bands: 指標の区分の境界。
    ///   - series: 指標の値の列。
    /// - Returns: `timeline.points` と同じ順の点ごとの分類。
    private func metricCategories(
        timeline: RouteAnalysisTimeline,
        bands: RouteAnalysisColorBands,
        series: RouteAnalysisValueSeries
    ) -> [RouteAnalysisColorCategory] {
        timeline.points.map { point in
            guard let value = matcher.value(at: point.date, in: series), let step = bands.step(for: value) else { return .noValue }
            return .ramp(step: step)
        }
    }

    /// 色分けの方法ごとの凡例を返します。
    ///
    /// 責務: `.none` は空、`.metric` は区分の範囲(値なしの辺がある時だけ「値なし」付き)、`.overlay` は重ね合わせの凡例を返します。
    /// - Parameters:
    ///   - coloring: 色分けの方法。
    ///   - includesNoValue: 描いた線に値なしの線があれば `true`。
    /// - Returns: 凡例の項目。
    private func legend(for coloring: RouteAnalysisColoring, includesNoValue: Bool) -> [RouteAnalysisLegendEntry] {
        switch coloring {
        case .none:
            return []
        case let .metric(metric, series):
            return legendBuilder.legend(metric: metric, unit: series.unit ?? metric.fallbackUnit, includesNoValue: includesNoValue)
        case let .overlay(overlay):
            return overlay.legend
        }
    }

    /// 強調の線を取り分けた点数まで間引き、色の区間の線の後ろの番号を振り直します。
    ///
    /// 責務: 各線の端点を残して点の合計を上限以下にし、firstID から順に番号を付けます。
    /// - Parameters:
    ///   - lines: 間引く前の強調の線。
    ///   - pointBudget: 強調の線の点の合計の上限。
    ///   - firstID: 最初の線に振る番号。
    /// - Returns: 間引いて番号を振り直した強調の線。
    private func simplifiedHighlights(_ lines: [RouteAnalysisMapLine], pointBudget: Int, firstID: Int) -> [RouteAnalysisMapLine] {
        let simplified = highlightSimplifier.simplify(lines.map(\.coordinates), pointBudget: pointBudget)
        return zip(lines, simplified).enumerated().map { offset, pair in
            RouteAnalysisMapLine(
                id: firstID + offset,
                coordinates: pair.1,
                category: pair.0.category,
                isApproximate: pair.0.isApproximate,
                isEmphasized: pair.0.isEmphasized
            )
        }
    }

    /// 端の印を並べます。
    ///
    /// 責務: 最初の点に出発の印を置き、2点以上ある時は最後の点に到着の印を足します。
    /// - Parameter points: 時刻の昇順の点列。
    /// - Returns: 出発(と到着)の印。点が無ければ空。
    private static func markers(of points: [RouteAnalysisTimelinePoint]) -> [RouteAnalysisMapMarker] {
        guard let first = points.first, let last = points.last else { return [] }
        var markers = [RouteAnalysisMapMarker(id: startMarkerID, coordinate: first.coordinate, endpoint: .start)]
        if points.count >= 2 {
            markers.append(RouteAnalysisMapMarker(id: endMarkerID, coordinate: last.coordinate, endpoint: .end))
        }
        return markers
    }
}
