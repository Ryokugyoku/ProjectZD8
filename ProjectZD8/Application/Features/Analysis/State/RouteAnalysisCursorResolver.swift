import Foundation

/// グラフで選んだ時刻から地図上の位置と値の読み出しを求め、地図で選んだ座標からグラフの時刻を求めます。
///
/// 数値の文字列化に既定の MainActor の `SessionLogAnalysisTextFormatter` を使うので、この型も既定の MainActor でメインから呼びます。
/// 探索は二分探索(時刻)と線形探索(座標)だけで軽いので、同期で処理します。
struct RouteAnalysisCursorResolver {
    /// 標高の単位です(ローカライズしません)。
    private static let elevationUnit = "m"

    /// 選んだ時刻から位置を採る時刻の差の上限(秒、ちょうどを含む)です。
    private let pointToleranceSeconds: TimeInterval
    /// 選んだ時刻に値を対応づける部品です。
    private let matcher: RouteAnalysisValueMatcher
    /// 地図で選んだ座標から点を採る距離の上限(m、ちょうどを含む)です。
    private let maximumSelectionDistanceMeters: Double
    /// 2点の距離を求める部品です。
    private let distance: GeoDistanceCalculator
    /// 数値と単位を文字列にする部品です。
    private let formatter: SessionLogAnalysisTextFormatter

    /// 探索の許容差と部品を固定して生成します。
    ///
    /// 責務: 時刻と距離の許容差、値の対応づけ・距離・文字列化の部品を保持します。
    /// - Parameters:
    ///   - pointToleranceSeconds: 選んだ時刻から位置を採る時刻の差の上限(秒)。既定は 5。
    ///   - matcher: 選んだ時刻に値を対応づける部品。
    ///   - maximumSelectionDistanceMeters: 地図で選んだ座標から点を採る距離の上限(m)。既定は 200。
    ///   - distance: 2点の距離を求める部品。
    ///   - formatter: 数値と単位を文字列にする部品。
    init(
        pointToleranceSeconds: TimeInterval = 5,
        matcher: RouteAnalysisValueMatcher = .init(),
        maximumSelectionDistanceMeters: Double = 200,
        distance: GeoDistanceCalculator = .init(),
        formatter: SessionLogAnalysisTextFormatter = .init()
    ) {
        self.pointToleranceSeconds = pointToleranceSeconds
        self.matcher = matcher
        self.maximumSelectionDistanceMeters = maximumSelectionDistanceMeters
        self.distance = distance
        self.formatter = formatter
    }

    /// グラフで選んだ時刻の読み出しを求めます。
    ///
    /// 責務: 時刻の差が許容差以内の最も近い点の座標と標高、値の対応づけの規則で選んだ指標の値を、文字列にして返します。
    /// - Parameters:
    ///   - date: 選んだ時刻。
    ///   - timeline: 時間の軸。
    ///   - values: 色分け中の指標の値の列。指標で色分けしていない時は `nil`。
    ///   - unit: 指標の値の単位。`nil` なら値の列の単位を使います。
    /// - Returns: 読み出し。位置・値・標高が無い時は、それぞれ `nil`。
    func cursor(at date: Date, timeline: RouteAnalysisTimeline, values: RouteAnalysisValueSeries?, unit: String?) -> RouteAnalysisCursor {
        let point = timeline.nearestPointIndex(to: date, within: pointToleranceSeconds).map { timeline.points[$0] }
        return RouteAnalysisCursor(
            date: date,
            coordinate: point?.coordinate,
            metricValueText: metricValueText(at: date, values: values, unit: unit),
            elevationText: point?.altitudeMeters.map { formatter.measurementText($0, unit: Self.elevationUnit) }
        )
    }

    /// 地図で選んだ座標に最も近い点の時刻を返します。
    ///
    /// 責務: 全点との距離を線形に比べ、最も近い点(同じ距離なら先の点)が距離の上限以内ならその時刻を返します。
    /// - Parameters:
    ///   - coordinate: 選んだ座標。
    ///   - timeline: 時間の軸。
    /// - Returns: 時刻。点が無い、または最も近い点でも上限より遠い時は `nil`。
    func date(nearestTo coordinate: GeoCoordinate, in timeline: RouteAnalysisTimeline) -> Date? {
        var nearest: (date: Date, meters: Double)?
        for point in timeline.points {
            let meters = distance.distanceMeters(coordinate, point.coordinate)
            if meters < nearest?.meters ?? .infinity {
                nearest = (point.date, meters)
            }
        }
        guard let nearest, nearest.meters <= maximumSelectionDistanceMeters else {
            return nil
        }
        return nearest.date
    }

    /// 選んだ時刻の指標の値を文字列にします。
    ///
    /// 責務: 値の対応づけの規則で値を選び、単位を付けて文字列にします(単位が無ければ数値だけ)。
    /// - Parameters:
    ///   - date: 選んだ時刻。
    ///   - values: 指標の値の列。
    ///   - unit: 指標の値の単位。
    /// - Returns: 値の文字列。列が無い、または対応する値が無い時は `nil`。
    private func metricValueText(at date: Date, values: RouteAnalysisValueSeries?, unit: String?) -> String? {
        guard let values, let value = matcher.value(at: date, in: values) else {
            return nil
        }
        guard let resolvedUnit = unit ?? values.unit, !resolvedUnit.isEmpty else {
            return formatter.measurementText(value, unit: "").trimmingCharacters(in: .whitespaces)
        }
        return formatter.measurementText(value, unit: resolvedUnit)
    }
}
