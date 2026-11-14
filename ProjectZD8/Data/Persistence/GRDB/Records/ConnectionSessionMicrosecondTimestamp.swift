import Foundation

/// 実時間とUnix epoch基準の整数microsecond列を相互変換します。
///
/// 取得証拠(`ConnectionSessionAcquisitionBatchRecord` など)と同じ最近傍丸めの規約を使用します。
nonisolated enum ConnectionSessionMicrosecondTimestamp {
    /// DateをUnix epoch基準の整数microsecondへ変換します。
    ///
    /// 責務: 有限かつInt64範囲内の時刻を最近傍microsecondへ丸めます。
    /// - Parameter date: 変換する日時。
    /// - Returns: Unix epochからの符号付きmicrosecond。
    /// - Throws: 非有限または表現範囲外の場合は `ConnectionSessionRepositoryError.integrityConflict`。
    static func microseconds(for date: Date) throws -> Int64 {
        let scaled = date.timeIntervalSince1970 * 1_000_000
        guard scaled.isFinite,
              scaled >= -9_223_372_036_854_775_808.0,
              scaled < 9_223_372_036_854_775_808.0 else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return Int64(scaled.rounded(.toNearestOrAwayFromZero))
    }

    /// Unix epoch基準の整数microsecondをDateへ変換します。
    ///
    /// 責務: 保存済みmicrosecond値を同じ規約の実時間へ復元します。
    /// - Parameter microseconds: Unix epochからの符号付きmicrosecond。
    /// - Returns: 対応する日時。
    static func date(fromMicroseconds microseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(microseconds) / 1_000_000)
    }
}
