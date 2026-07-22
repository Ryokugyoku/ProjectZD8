import Foundation

/// PID時系列の1系列を用途別表示と折れ線グラフへ渡す状態です。
struct SessionPIDSeries: Identifiable, Equatable, Sendable {
    /// 折れ線上の1観測点です。
    struct Point: Identifiable, Equatable, Sendable {
        /// Rawログ順序に由来する安定識別子です。
        let id: Int64
        /// 応答を観測した日時です。
        let observedAt: Date
        /// 数式変換後の値です。
        let value: Double
    }

    /// ServiceとPIDからなる系列識別子です。
    let id: OBDPIDRequest
    /// PID定義が提供する表示名キーです。
    let nameKey: String?
    /// 数値の単位です。
    let unit: String
    /// 車種専用PIDの場合に表示する型式です。
    let vehicleModelCode: String?
    /// 元タイムラインに存在するこのPIDの数値化済み総件数です。
    let totalPointCount: Int
    /// 全数値化済み観測の最小値です。
    let minimumValue: Double
    /// 全数値化済み観測の算術平均です。
    let averageValue: Double
    /// 全数値化済み観測の最大値です。
    let maximumValue: Double
    /// セッション内で最後に観測した数値です。
    let latestValue: Double
    /// PIDの意味とグラフから観察できる内容を説明するローカライズキーです。
    let interpretationKey: String
    /// セッション内の観測順に並ぶ表示用代表点です。
    let points: [Point]
}

/// 観測値が属した数値帯と推定滞在時間です。
struct SessionDurationBand: Identifiable, Equatable, Sendable {
    /// 数値帯の下限を安定識別子として使用します。
    var id: Double { lowerBound }
    /// 数値帯に含める下限値です。
    let lowerBound: Double
    /// 数値帯から除外する上限値です。
    let upperBound: Double
    /// 長い欠測を除いた観測間隔の合計秒数です。
    let duration: TimeInterval
    /// 同じPIDで集計できた全時間に占める割合です。
    let proportion: Double
}

/// 1セッションの走行傾向を表す集計状態です。
struct SessionPerformanceSummary: Equatable, Sendable {
    /// データがない初期状態です。
    static let empty = SessionPerformanceSummary(
        speedBands: [],
        rpmBands: [],
        estimatedMovingDuration: nil,
        estimatedDistanceKilometers: nil
    )
    /// 車速を10 km/h単位へ集計した上位帯です。
    let speedBands: [SessionDurationBand]
    /// 回転数を500 rpm単位へ集計した上位帯です。
    let rpmBands: [SessionDurationBand]
    /// 車速が1 km/h以上だった信頼できる観測間隔の合計です。
    let estimatedMovingDuration: TimeInterval?
    /// 車速観測を時間積分した参考走行距離です。
    let estimatedDistanceKilometers: Double?
}

/// 車両部品・系統に結び付く1件の観測要約です。
struct SessionComponentInsight: Identifiable, Equatable, Sendable {
    /// 部品・系統の表示分類です。
    enum Component: String, Equatable, Sendable {
        /// ECU電源電圧から観察する充電・電源系です。
        case electrical
        /// 冷却水温または油温から観察する冷却・潤滑系です。
        case thermal
        /// 燃料補正または吸入空気量から観察する燃料・吸気系です。
        case fuelAndIntake
        /// 触媒またはDPF温度から観察する排気後処理系です。
        case exhaust
        /// 故障コード消去後またはMIL点灯中の累積距離から観察する診断履歴です。
        case diagnostics
    }

    /// 対象PIDを安定識別子として使用します。
    var id: OBDPIDRequest { series.id }
    /// 観察対象の部品・系統です。
    let component: Component
    /// 集計値と説明を提供するPID系列です。
    let series: SessionPIDSeries
}

/// 2件のPIDを近接時刻で対応付けた散布図状態です。
struct SessionPIDRelationship: Identifiable, Equatable, Sendable {
    /// 散布図上の1対応点です。
    struct Point: Identifiable, Equatable, Sendable {
        /// 対応元系列のRawログ順序に由来する安定識別子です。
        let id: Int64
        /// 横軸PIDの値です。
        let x: Double
        /// 縦軸PIDの値です。
        let y: Double
    }

    /// PID組を表す安定識別子です。
    let id: String
    /// 横軸へ使用するPID系列です。
    let xSeries: SessionPIDSeries
    /// 縦軸へ使用するPID系列です。
    let ySeries: SessionPIDSeries
    /// 近接時刻で対応付けられた散布点です。
    let points: [Point]
}

/// バックグラウンド集計から一括反映するグラフ表示状態です。
struct SessionLogVisualizationSnapshot: Equatable, Sendable {
    /// Service/PID単位の折れ線系列です。
    let series: [SessionPIDSeries]
    /// 速度帯と回転域の推定滞在時間をまとめた走行サマリーです。
    let performanceSummary: SessionPerformanceSummary
    /// 取得できたPIDを部品・系統へ結び付けた観察候補です。
    let componentInsights: [SessionComponentInsight]
    /// 近接時刻で対応付けた代表PID組です。
    let relationships: [SessionPIDRelationship]
}

/// 数値化済みPID時系列を用途別系列と代表的な相関候補へ変換します。
enum SessionLogVisualizationBuilder {
    /// 1系列のグラフへ渡す最大代表点数です。
    private static let maximumChartPointCount = 600
    /// 散布図で比較する標準PIDの組です。
    private static let relationshipPairs: [(OBDPIDRequest, OBDPIDRequest)] = [
        (.init(service: 0x01, pid: 0x0C), .init(service: 0x01, pid: 0x0D)),
        (.init(service: 0x01, pid: 0x0C), .init(service: 0x01, pid: 0x04)),
        (.init(service: 0x01, pid: 0x0C), .init(service: 0x01, pid: 0x10)),
        (.init(service: 0x01, pid: 0x11), .init(service: 0x01, pid: 0x04)),
        (.init(service: 0x01, pid: 0x06), .init(service: 0x01, pid: 0x07)),
        (.init(service: 0x01, pid: 0x0D), .init(service: 0x21, pid: 0x17))
    ]

    /// 解析済みタイムラインから全グラフ表示状態を一度だけ構築します。
    ///
    /// 責務: 1件の解析済みタイムラインを用途別、折れ線、散布図の表示スナップショットへ変換します。
    /// - Parameter timeline: Raw順序と数値化結果を保持する解析済みサンプル。
    /// - Returns: 各表示で共有する不変なグラフ表示状態。
    static func build(from timeline: [SessionLogAnalysisState.TimelineSample]) -> SessionLogVisualizationSnapshot {
        let series = series(from: timeline)
        return SessionLogVisualizationSnapshot(
            series: series,
            performanceSummary: performanceSummary(from: timeline),
            componentInsights: componentInsights(from: series),
            relationships: relationships(from: series)
        )
    }

    /// 数値化済みサンプルをService/PID単位の折れ線系列へまとめます。
    ///
    /// 責務: 1件の解析済みタイムラインを数値化可能なPID系列の一覧へ変換します。
    /// - Parameter timeline: Raw順序と数値化結果を保持する解析済みサンプル。
    /// - Returns: Service/PID順で安定整列した数値系列。
    static func series(from timeline: [SessionLogAnalysisState.TimelineSample]) -> [SessionPIDSeries] {
        let decoded = timeline.compactMap { sample -> (OBDPIDRequest, SessionLogAnalysisState.TimelineSample, Double)? in
            guard let value = sample.value else { return nil }
            return (.init(service: sample.service, pid: sample.pid), sample, value)
        }
        return Dictionary(grouping: decoded, by: { $0.0 })
            .map { request, samples in
                let first = samples[0].1
                let values = samples.map(\.2)
                return SessionPIDSeries(
                    id: request,
                    nameKey: first.nameKey,
                    unit: first.unit ?? "",
                    vehicleModelCode: first.vehicleModelCode,
                    totalPointCount: samples.count,
                    minimumValue: values.min() ?? 0,
                    averageValue: values.reduce(0, +) / Double(values.count),
                    maximumValue: values.max() ?? 0,
                    latestValue: samples.last?.2 ?? 0,
                    interpretationKey: interpretationKey(for: request),
                    points: sampledPoints(samples.map {
                        SessionPIDSeries.Point(id: $0.1.sequence, observedAt: $0.1.observedAt, value: $0.2)
                    })
                )
            }
            .sorted { lhs, rhs in
                lhs.id.service == rhs.id.service
                    ? lhs.id.pid < rhs.id.pid
                    : lhs.id.service < rhs.id.service
            }
    }

    /// PIDの意味と折れ線から観察できる内容を説明キーへ変換します。
    ///
    /// 責務: 1件の標準PID識別子を推測を含まない観察ガイドへ分類します。
    /// - Parameter request: 説明するService/PID識別子。
    /// - Returns: PID固有または用途分類の説明ローカライズキー。
    private static func interpretationKey(for request: OBDPIDRequest) -> String {
        if request == OBDPIDRequest(service: 0x21, pid: 0x02) { return "analysis.trend.guide.zd8_distance" }
        if request == OBDPIDRequest(service: 0x21, pid: 0x17) { return "analysis.trend.guide.zd8_atf" }
        guard request.service == 0x01 else { return "analysis.trend.guide.generic" }
        switch request.pid {
        case 0x0C: return "analysis.trend.guide.rpm"
        case 0x0D: return "analysis.trend.guide.speed"
        case 0x04: return "analysis.trend.guide.load"
        case 0x05: return "analysis.trend.guide.coolant"
        case 0x06...0x09: return "analysis.trend.guide.fuel_trim"
        case 0x10: return "analysis.trend.guide.maf"
        case 0x11, 0x45, 0x47...0x4C, 0x5A, 0x8D: return "analysis.trend.guide.throttle"
        case 0x1F: return "analysis.trend.guide.runtime"
        case 0x21: return "analysis.trend.guide.mil_distance"
        case 0x31: return "analysis.trend.guide.codes_cleared_distance"
        case 0xA6: return "analysis.trend.guide.odometer"
        case 0x3C...0x3F, 0x7C: return "analysis.trend.guide.exhaust_temperature"
        case 0x42: return "analysis.trend.guide.voltage"
        case 0x5C: return "analysis.trend.guide.oil_temperature"
        default: return "analysis.trend.guide.generic"
        }
    }

    /// 速度帯、回転域、車速積算距離をタイムラインから集計します。
    ///
    /// 責務: 1件の解析済みタイムラインを走行サマリー表示状態へ変換します。
    /// - Parameter timeline: 数値化結果を含む全観測。
    /// - Returns: 長い欠測区間を除外した時間帯ランキングと参考距離。
    private static func performanceSummary(from timeline: [SessionLogAnalysisState.TimelineSample]) -> SessionPerformanceSummary {
        let speed = decodedPoints(for: .init(service: 0x01, pid: 0x0D), from: timeline)
        let rpm = decodedPoints(for: .init(service: 0x01, pid: 0x0C), from: timeline)
        return SessionPerformanceSummary(
            speedBands: durationBands(points: speed, width: 10),
            rpmBands: durationBands(points: rpm, width: 500),
            estimatedMovingDuration: estimatedMovingDuration(from: speed),
            estimatedDistanceKilometers: estimatedDistance(from: speed)
        )
    }

    /// 指定PIDの数値化済み観測を時刻順で返します。
    ///
    /// 責務: 全タイムラインから1件のPIDに属する有限数値観測だけを抽出します。
    /// - Parameters:
    ///   - request: 抽出するService/PID識別子。
    ///   - timeline: 抽出元の全観測。
    /// - Returns: 観測時刻で昇順にした有限数値点。
    private static func decodedPoints(
        for request: OBDPIDRequest,
        from timeline: [SessionLogAnalysisState.TimelineSample]
    ) -> [SessionPIDSeries.Point] {
        timeline.compactMap { sample in
            guard sample.service == request.service, sample.pid == request.pid,
                  let value = sample.value, value.isFinite else { return nil }
            return SessionPIDSeries.Point(id: sample.sequence, observedAt: sample.observedAt, value: value)
        }
        .sorted { $0.observedAt < $1.observedAt }
    }

    /// 一定幅の数値帯ごとに信頼できる観測間隔を合計します。
    ///
    /// 責務: 1件の時系列を長い欠測を含めない推定滞在時間ランキングへ変換します。
    /// - Parameters:
    ///   - points: 時刻順の数値観測。
    ///   - width: 1区間の数値幅。
    /// - Returns: 滞在時間の長い順で最大5件の数値帯。
    private static func durationBands(points: [SessionPIDSeries.Point], width: Double) -> [SessionDurationBand] {
        let intervals = reliableIntervals(points)
        var durations: [Double: TimeInterval] = [:]
        for (point, duration) in intervals {
            let lowerBound = floor(max(point.value, 0) / width) * width
            durations[lowerBound, default: 0] += duration
        }
        let total = durations.values.reduce(0, +)
        guard total > 0 else { return [] }
        var bands: [SessionDurationBand] = []
        bands.reserveCapacity(durations.count)
        for (lowerBound, duration) in durations {
            bands.append(SessionDurationBand(
                lowerBound: lowerBound,
                upperBound: lowerBound + width,
                duration: duration,
                proportion: duration / total
            ))
        }
        bands.sort { lhs, rhs in
            lhs.duration == rhs.duration ? lhs.lowerBound < rhs.lowerBound : lhs.duration > rhs.duration
        }
        return Array(bands.prefix(5))
    }

    /// 代表的な観測周期から外れる長い空白を除いた隣接間隔を返します。
    ///
    /// 責務: 1件の時系列を継続観測とみなせる点と秒数の組へ変換します。
    /// - Parameter points: 時刻順の数値観測。
    /// - Returns: 中央観測周期の3倍以下かつ10秒以下の正の隣接間隔。
    private static func reliableIntervals(_ points: [SessionPIDSeries.Point]) -> [(SessionPIDSeries.Point, TimeInterval)] {
        guard points.count >= 2 else { return [] }
        let gaps = zip(points, points.dropFirst()).map { $1.observedAt.timeIntervalSince($0.observedAt) }.filter { $0 > 0 }
        guard !gaps.isEmpty else { return [] }
        let sortedGaps = gaps.sorted()
        let median = sortedGaps[sortedGaps.count / 2]
        let maximumGap = min(max(median * 3, 1), 10)
        return zip(points, points.dropFirst()).compactMap { current, next in
            let gap = next.observedAt.timeIntervalSince(current.observedAt)
            return gap > 0 && gap <= maximumGap ? (current, gap) : nil
        }
    }

    /// 車速と信頼できる観測間隔から走行距離を台形積分します。
    ///
    /// 責務: 1件の車速時系列を欠測区間を含まない参考走行距離へ変換します。
    /// - Parameter points: 時刻順の車速観測。
    /// - Returns: 積分できた場合のキロメートル値。
    private static func estimatedDistance(from points: [SessionPIDSeries.Point]) -> Double? {
        let intervals = reliableIntervals(points)
        guard !intervals.isEmpty else { return nil }
        let indexed = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        let ordered = points.enumerated().reduce(into: [Int64: SessionPIDSeries.Point]()) { result, pair in
            guard pair.offset + 1 < points.count else { return }
            result[pair.element.id] = points[pair.offset + 1]
        }
        let kilometers = intervals.reduce(0.0) { result, interval in
            guard indexed[interval.0.id] != nil, let next = ordered[interval.0.id] else { return result }
            return result + max(interval.0.value + next.value, 0) / 2 * interval.1 / 3_600
        }
        return kilometers
    }

    /// 走行状態だった信頼できる車速観測間隔を合計します。
    ///
    /// 責務: 1件の車速時系列を1 km/h以上だった参考走行時間へ変換します。
    /// - Parameter points: 時刻順の車速観測。
    /// - Returns: 集計できた場合の推定走行秒数。
    private static func estimatedMovingDuration(from points: [SessionPIDSeries.Point]) -> TimeInterval? {
        let intervals = reliableIntervals(points)
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0) { result, interval in
            result + (interval.0.value >= 1 ? interval.1 : 0)
        }
    }

    /// 取得済み系列から部品・系統単位で説明できるPIDを抽出します。
    ///
    /// 責務: 1件のPID系列一覧を根拠PID付きの部品・系統観察候補へ変換します。
    /// - Parameter series: 数値化済みPID系列。
    /// - Returns: 電源、熱、吸排気の順に安定整列した観察候補。
    private static func componentInsights(from series: [SessionPIDSeries]) -> [SessionComponentInsight] {
        series.compactMap { item in
            let component: SessionComponentInsight.Component?
            switch (item.id.service, item.id.pid) {
            case (0x01, 0x42): component = .electrical
            case (0x01, 0x05), (0x01, 0x5C), (0x21, 0x17): component = .thermal
            case (0x01, 0x06...0x09), (0x01, 0x10): component = .fuelAndIntake
            case (0x01, 0x3C...0x3F), (0x01, 0x7C): component = .exhaust
            case (0x01, 0x21), (0x01, 0x31), (0x21, 0x02): component = .diagnostics
            default: component = nil
            }
            return component.map { SessionComponentInsight(component: $0, series: item) }
        }
        .sorted { lhs, rhs in
            lhs.component.rawValue == rhs.component.rawValue
                ? lhs.series.id.pid < rhs.series.id.pid
                : lhs.component.rawValue < rhs.component.rawValue
        }
    }

    /// 先頭と末尾を含む等間隔の代表点へ表示用系列を縮約します。
    ///
    /// 責務: 1件の数値時系列をRaw件数を変えずグラフ描画上限内の代表点へ変換します。
    /// - Parameter points: 観測順に並ぶ全数値点。
    /// - Returns: 上限以下の場合は元配列、それ以外は先頭と末尾を含む代表点。
    private static func sampledPoints(_ points: [SessionPIDSeries.Point]) -> [SessionPIDSeries.Point] {
        guard points.count > maximumChartPointCount else { return points }
        let stride = Double(points.count - 1) / Double(maximumChartPointCount - 1)
        return (0..<maximumChartPointCount).map { index in
            points[Int((Double(index) * stride).rounded())]
        }
    }

    /// 代表的なPID組を近接観測時刻で対応付けます。
    ///
    /// 責務: 1件のPID系列一覧を3秒以内の近接点を持つ代表散布図の一覧へ変換します。
    /// - Parameter series: 対応付ける数値化済みPID系列。
    /// - Returns: 2点以上を生成できた標準PID組の散布図状態。
    static func relationships(from series: [SessionPIDSeries]) -> [SessionPIDRelationship] {
        let indexed = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        return relationshipPairs.compactMap { xID, yID in
            guard let xSeries = indexed[xID], let ySeries = indexed[yID] else { return nil }
            let points = nearestPoints(xSeries: xSeries, ySeries: ySeries)
            guard points.count >= 2 else { return nil }
            return SessionPIDRelationship(
                id: "\(xID.service)-\(xID.pid)-\(yID.service)-\(yID.pid)",
                xSeries: xSeries,
                ySeries: ySeries,
                points: points
            )
        }
    }

    /// 横軸の各点へ3秒以内で最も近い縦軸点を対応付けます。
    ///
    /// 責務: 2件の時系列を順序を保った近接時刻の散布点へ変換します。
    /// - Parameters:
    ///   - xSeries: 横軸へ使用する時系列。
    ///   - ySeries: 縦軸へ使用する時系列。
    /// - Returns: 観測時刻差が3秒以内の近接点。
    private static func nearestPoints(
        xSeries: SessionPIDSeries,
        ySeries: SessionPIDSeries
    ) -> [SessionPIDRelationship.Point] {
        var yIndex = 0
        return xSeries.points.compactMap { xPoint in
            while yIndex + 1 < ySeries.points.count,
                  abs(ySeries.points[yIndex + 1].observedAt.timeIntervalSince(xPoint.observedAt))
                    <= abs(ySeries.points[yIndex].observedAt.timeIntervalSince(xPoint.observedAt)) {
                yIndex += 1
            }
            let yPoint = ySeries.points[yIndex]
            guard abs(yPoint.observedAt.timeIntervalSince(xPoint.observedAt)) <= 3 else { return nil }
            return SessionPIDRelationship.Point(id: xPoint.id, x: xPoint.value, y: yPoint.value)
        }
    }
}
