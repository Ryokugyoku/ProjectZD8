import Foundation

/// 走行時間(秒)を「時:分:秒」または「分:秒」の文字列へ整形します。SwiftUIに依存しない純粋型で、アプリとWidget Extensionの両方に属します。
nonisolated enum RecordingSessionLiveActivityDurationFormatter {
    /// 秒数を、1時間未満は `m:ss`、1時間以上は `h:mm:ss` へ整形します。
    ///
    /// 責務: 秒数を切り捨てた整数秒にし、負の値や有限でない値は0秒として整形します。
    /// - Parameter seconds: 整形する秒数。
    /// - Returns: 整形済みの文字列。
    static func string(seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 {
            return "\(hours):" + twoDigits(minutes) + ":" + twoDigits(rest)
        }
        return "\(minutes):" + twoDigits(rest)
    }

    /// 0〜59の整数を2桁へ整えます。
    ///
    /// 責務: 1桁なら先頭へ0を付けます。
    /// - Parameter value: 整える整数。
    /// - Returns: 2桁の文字列。
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
