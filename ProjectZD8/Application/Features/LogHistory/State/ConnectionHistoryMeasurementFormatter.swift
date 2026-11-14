import Foundation

/// 接続履歴画面の走行時間と走行距離を単位付き文字列へ変換します。
///
/// iOS と macOS の履歴画面で共通に使う純粋な表示変換で、ロケールとカレンダーを注入できます。
struct ConnectionHistoryMeasurementFormatter {
    /// 時分表記に使うカレンダーです。ロケール依存の単位名はこのカレンダーのロケールに従います。
    let calendar: Calendar
    /// 距離表記の数値整形に使うロケールです。
    let locale: Locale

    /// 表示に使うカレンダーとロケールを固定して生成します。
    ///
    /// 責務: 時間と距離の整形に使うロケール依存の設定を1組にまとめます。
    /// - Parameters:
    ///   - calendar: 時分表記に使うカレンダー。既定は現在の自動更新カレンダー。
    ///   - locale: 距離表記に使うロケール。既定は現在ロケール。
    init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    /// 秒数を単位名が明確な時分表記へ変換します。
    ///
    /// 責務: 1件の秒数を3600秒以上は時と分、未満は分だけの固定幅時間文字列へ変換します。
    /// - Parameter interval: 表示する秒数。負値は0秒として扱います。
    /// - Returns: 短い単位名と0埋めを使った時間文字列。
    func durationText(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = interval >= 3_600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, interval)) ?? String(localized: "history.duration.zero")
    }

    /// セッション差分をメートルまたはキロメートルの明確な距離表記へ変換します。
    ///
    /// 責務: 1件の任意走行距離を距離単位付き表示または非対応表示へ変換します。
    /// - Parameter kilometers: A6累積値の差分。確定できない場合は `nil`。
    /// - Returns: 1 km未満はm、1 km以上はkm、未確定時は走行距離非対応の文字列。
    func distanceText(_ kilometers: Double?) -> String {
        guard let kilometers else { return String(localized: "history.distance.unsupported") }
        if kilometers < 1 { return String(format: "%.0f m", locale: locale, kilometers * 1_000) }
        return String(format: "%.1f km", locale: locale, kilometers)
    }

    /// セッションの確定走行時間を返します。
    ///
    /// 責務: 1件のセッションの開始・終了日時から非負の記録時間を算出します。
    /// - Parameter session: 時間を求めるセッション。
    /// - Returns: 秒単位の非負記録時間。終了日時が無い場合は0。
    func sessionDuration(_ session: ConnectionSession) -> TimeInterval {
        max(0, session.endedAt?.timeIntervalSince(session.startedAt) ?? 0)
    }
}
