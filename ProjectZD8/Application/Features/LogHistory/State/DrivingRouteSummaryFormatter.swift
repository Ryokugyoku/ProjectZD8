import Foundation

/// 走行ルートの要約(長さ・記録できた時間・記録できた割合)を表示用の文字列へ整形します。
///
/// 長さと時間は履歴画面と同じ `ConnectionHistoryMeasurementFormatter` の表記(1 km 未満は m、以上は km の小数1桁)に揃えます。
struct DrivingRouteSummaryFormatter {
    /// 割合が無い時に出す文字列です。
    static let unavailableCoverageText = "—"

    /// 長さと時間の整形です。
    private let measurement: ConnectionHistoryMeasurementFormatter
    /// 割合の整形に使うロケールです。
    private let locale: Locale

    /// 整形に使う部品とロケールを固定して生成します。
    ///
    /// 責務: 長さ・時間の整形と、割合のロケールを保持します。
    /// - Parameters:
    ///   - measurement: 長さと時間の整形。
    ///   - locale: 割合の整形に使うロケール。
    init(measurement: ConnectionHistoryMeasurementFormatter = .init(), locale: Locale = .current) {
        self.measurement = measurement
        self.locale = locale
    }

    /// 要約を表示用の文字列へ整形します。
    ///
    /// 責務: 長さ・記録できた時間・記録できた割合を、それぞれ単位付きの文字列にします。
    /// - Parameter summary: 走行ルートの要約。
    /// - Returns: 表示用の文字列。割合が無ければ割合は "—"。
    func text(for summary: DrivingRouteSummary) -> DrivingRouteSummaryText {
        DrivingRouteSummaryText(
            lengthText: measurement.distanceText(summary.lengthMeters / 1_000),
            recordedDurationText: measurement.durationText(summary.recordedDuration),
            coverageText: coverageText(summary.coverageRatio)
        )
    }

    /// 記録できた割合を整数の百分率へ整形します。
    ///
    /// 責務: 割合をロケールに従う百分率(小数なし)にし、無ければ "—" にします。
    /// - Parameter ratio: 記録できた割合(0...1)。
    /// - Returns: 百分率の文字列。
    private func coverageText(_ ratio: Double?) -> String {
        guard let ratio else {
            return Self.unavailableCoverageText
        }
        return ratio.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
