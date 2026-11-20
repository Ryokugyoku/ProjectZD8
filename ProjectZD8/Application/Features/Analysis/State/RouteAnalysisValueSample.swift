import Foundation

/// 指標の値1件です。
nonisolated struct RouteAnalysisValueSample: Equatable, Sendable {
    /// 時計の選び方で揃えた時刻です。
    let date: Date
    /// 有限の値です。
    let value: Double
}
