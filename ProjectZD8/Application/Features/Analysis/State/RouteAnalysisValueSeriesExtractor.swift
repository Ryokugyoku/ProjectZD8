import Foundation

/// 解析の時系列から、1つの PID の値の列と、時計の判定に使う時刻の組を取り出します。
nonisolated struct RouteAnalysisValueSeriesExtractor: Sendable {
    /// 並べ替えの途中で使う、揃えた時刻と元の連番の付いた値です。
    private typealias OrderedValue = (date: Date, sequence: Int64, value: Double, unit: String?)

    /// 時系列の全サンプルの時刻の組を返します。
    ///
    /// 責務: 値の有無を問わず、Raw の行ごとの実時間と単調時刻を写します(時計の選び方の判定に使います)。
    /// - Parameter timeline: 解析の時系列。
    /// - Returns: 時系列の順の時刻の組。
    func clockStamps(in timeline: [SessionLogAnalysisState.TimelineSample]) -> [TelemetryClockStamp] {
        timeline.map { TelemetryClockStamp(observedAt: $0.observedAt, monotonicNanoseconds: $0.monotonicNanoseconds) }
    }

    /// 1つの PID の値の列を取り出します。
    ///
    /// 責務: service と pid が一致し、値が有限のサンプルだけを、揃えた時刻の昇順(同じ時刻は sequence の順)に並べます。
    /// 単位は並べた順で最初の `nil` でない単位です。
    /// - Parameters:
    ///   - pid: 取り出す PID。
    ///   - timeline: 解析の時系列。
    ///   - alignment: 時計の選び方。
    /// - Returns: 値の列(該当が無ければ空)。
    func series(
        for pid: OBDPIDRequest,
        in timeline: [SessionLogAnalysisState.TimelineSample],
        alignment: TelemetryTimeAlignment
    ) -> RouteAnalysisValueSeries {
        let ordered = timeline
            .compactMap { orderedValue(of: $0, matching: pid, alignment: alignment) }
            .sorted { lhs, rhs in lhs.date != rhs.date ? lhs.date < rhs.date : lhs.sequence < rhs.sequence }
        return RouteAnalysisValueSeries(
            pid: pid,
            unit: ordered.lazy.compactMap(\.unit).first,
            samples: ordered.map { RouteAnalysisValueSample(date: $0.date, value: $0.value) }
        )
    }

    /// 1件のサンプルを、対象の PID の有限の値なら並べ替え用の値にします。
    ///
    /// 責務: service・pid の一致と値の有限を確かめ、時刻を揃えます。
    /// - Parameters:
    ///   - sample: 解析の時系列の1件。
    ///   - pid: 取り出す PID。
    ///   - alignment: 時計の選び方。
    /// - Returns: 並べ替え用の値。対象外なら `nil`。
    private func orderedValue(
        of sample: SessionLogAnalysisState.TimelineSample,
        matching pid: OBDPIDRequest,
        alignment: TelemetryTimeAlignment
    ) -> OrderedValue? {
        guard sample.service == pid.service, sample.pid == pid.pid,
              let value = sample.value, value.isFinite
        else {
            return nil
        }
        let stamp = TelemetryClockStamp(observedAt: sample.observedAt, monotonicNanoseconds: sample.monotonicNanoseconds)
        return (alignment.date(for: stamp), sample.sequence, value, sample.unit)
    }
}
