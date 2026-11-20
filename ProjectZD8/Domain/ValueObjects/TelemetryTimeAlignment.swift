import Foundation

/// 位置と PID の値を同じ時間の軸に並べる時の、時計の選び方です。
nonisolated enum TelemetryTimeAlignment: Equatable, Sendable {
    /// 実時間(`observedAt`)をそのまま使います。
    case wallClock
    /// 単調時刻に差を足して実時間の枠へ直します。Date(参照日からの秒) = 単調秒 + `referenceOffsetSeconds` です。
    case monotonic(referenceOffsetSeconds: Double)

    /// 1件の観測の時刻を、この時計の選び方で Date に直します。
    ///
    /// 責務: 実時間ならそのまま、単調時計なら単調秒に差を足した参照日からの秒を返します。
    /// - Parameter stamp: 直す観測の時刻。
    /// - Returns: 揃えた時刻。単調時計で単調時刻が `nil` の時は `observedAt`。
    func date(for stamp: TelemetryClockStamp) -> Date {
        switch self {
        case .wallClock:
            return stamp.observedAt
        case .monotonic(let referenceOffsetSeconds):
            guard let nanoseconds = stamp.monotonicNanoseconds else { return stamp.observedAt }
            let seconds = Double(nanoseconds) / 1_000_000_000
            return Date(timeIntervalSinceReferenceDate: seconds + referenceOffsetSeconds)
        }
    }
}
