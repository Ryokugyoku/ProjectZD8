import Foundation

/// 計測値を表示用の数値文字列へ整形します。SwiftUIに依存しない純粋型で、アプリとWidget Extensionの両方に属します。
nonisolated enum RecordingSessionLiveActivityMetricFormatter {
    /// 計測値を整数に丸めた表示用の文字列へ整形します。
    ///
    /// 責務: 取得済みの有限な数値だけを地域設定に沿った整数表記にし、それ以外は未取得として `nil` を返します。
    /// - Parameters:
    ///   - metric: 整形する計測値。
    ///   - locale: 桁区切りなどに使う地域設定。
    /// - Returns: 整形済みの文字列。未取得または有限でない値なら `nil`。
    static func formattedValue(
        of metric: RecordingSessionActivityAttributes.Metric,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard case .value(let value) = metric, value.isFinite else { return nil }
        return value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}
