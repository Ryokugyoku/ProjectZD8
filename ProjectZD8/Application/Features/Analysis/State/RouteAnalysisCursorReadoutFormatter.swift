import Foundation

/// グラフで選んだ時刻の読み出し(時刻の文字・位置が無い時の案内)を整形します。SwiftUI に依存しない純粋型です。
///
/// iOS と macOS の解析画面で共有します。値と標高の文字は `RouteAnalysisCursor` が持つものをそのまま使います。
nonisolated struct RouteAnalysisCursorReadoutFormatter: Sendable {
    /// 位置が無い時の案内のローカライズキーです。
    private static let noPositionKey = "analysis.route.cursor.no_position"

    /// 時刻の書式に使うロケールです。
    private let locale: Locale
    /// 時刻の書式に使うタイムゾーンです。
    private let timeZone: TimeZone

    /// 書式の条件を受け取って作ります。
    ///
    /// 責務: 時刻の書式に使うロケールとタイムゾーンを保持します。
    /// - Parameters:
    ///   - locale: 時刻の書式に使うロケール。
    ///   - timeZone: 時刻の書式に使うタイムゾーン。
    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.locale = locale
        self.timeZone = timeZone
    }

    /// 選んだ時刻を時・分・秒の文字にします。
    ///
    /// 責務: ロケールとタイムゾーンに従い、日付を含まない時・分・秒の文字へ変換します。
    /// - Parameter date: 選んだ時刻。
    /// - Returns: 時・分・秒の文字(例: ja なら `9:05:07`、en なら `9:05:07 AM`)。
    func timeText(for date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .standard, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// 位置が無い時の案内のローカライズキーを返します。
    ///
    /// 責務: 読み出しに位置が無い時だけ「この時刻の位置はありません」のキーを返します。
    /// - Parameter cursor: グラフで選んだ時刻の読み出し。
    /// - Returns: 位置が無ければ案内のキー、あれば `nil`。
    func positionMessageKey(for cursor: RouteAnalysisCursor) -> String? {
        cursor.coordinate == nil ? Self.noPositionKey : nil
    }
}
