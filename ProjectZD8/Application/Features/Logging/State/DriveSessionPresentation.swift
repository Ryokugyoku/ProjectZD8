import Foundation

/// 記録中の表示に使う文字列整形です。
nonisolated enum DriveSessionPresentation {
    /// 責務: 経過時間を `M:SS`、1時間以上は `H:MM:SS` で返します。負の値は 0 として扱います。
    static func elapsedText(microseconds: Int64) -> String {
        let total = Int(max(0, microseconds) / 1_000_000)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// 責務: 走行距離(km)を、ロケールの道路用単位で小数1桁に整形します。
    static func distanceText(kilometers: Double, locale: Locale = .current) -> String {
        Measurement(value: kilometers, unit: UnitLength.kilometers).formatted(
            .measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1)))
                .locale(locale)
        )
    }

    /// 責務: 応答率(0...1)を百分率の整数で整形します。
    static func responseRateText(_ rate: Double, locale: Locale = .current) -> String {
        rate.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// 責務: セッションの終了理由の表示用ローカライズキーを返します。
    static func endReasonKey(_ reason: SessionEndReason) -> String {
        "drive.endReason.\(reason.rawValue)"
    }
}
