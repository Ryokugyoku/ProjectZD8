import Foundation
@testable import ProjectZD8

/// 値の列(`RouteAnalysisValueSeries`)を、基準からの秒と値の組から作るテストの補助です。
enum RouteAnalysisValueSeriesFixtures {
    /// 秒と値の組から値の列を作ります。
    ///
    /// 責務: 与えた順(昇順の前提)に、`RouteAnalysisTimelinePointFixtures.base` からの秒の時刻で標本を並べます。
    /// - Parameters:
    ///   - samples: 基準からの秒と値の組。
    ///   - metric: 列の PID を決める指標。
    ///   - unit: 列の単位。
    /// - Returns: 値の列。
    static func series(
        _ samples: [(seconds: TimeInterval, value: Double)],
        metric: RouteAnalysisColorMetric = .vehicleSpeed,
        unit: String? = "km/h"
    ) -> RouteAnalysisValueSeries {
        let values: [RouteAnalysisValueSample] = samples.map {
            RouteAnalysisValueSample(date: RouteAnalysisTimelinePointFixtures.base.addingTimeInterval($0.seconds), value: $0.value)
        }
        return RouteAnalysisValueSeries(pid: metric.pid, unit: unit, samples: values)
    }
}
