import Foundation

/// 履歴へ同時に適用する絞り込み条件です。
nonisolated struct LogHistoryFilter: Equatable, Sendable {
    /// 開始日の下限です(その日の0時から)。
    var startDate: Date?
    /// 開始日の上限です(その日の終わりまで)。
    var endDate: Date?
    /// 終了理由です。`nil` なら全ての理由です。
    var endReason: SessionEndReason?
    var dataKind: LogHistoryDataKindFilter = .all

    /// 条件が1つでも有効かどうかです。
    var isActive: Bool { startDate != nil || endDate != nil || endReason != nil || dataKind != .all }

    /// 行が全条件を満たすかを返します。
    ///
    /// 責務: 開始日の範囲・終了理由・実車/デモの条件で1行を判定します。
    /// - Parameters:
    ///   - row: 判定する行。
    ///   - calendar: 日付境界の判定に使うカレンダー。
    func matches(_ row: LogHistorySessionRow, calendar: Calendar = .current) -> Bool {
        if let startDate, row.startedAt < calendar.startOfDay(for: startDate) { return false }
        if let endDate {
            let dayStart = calendar.startOfDay(for: endDate)
            let limit = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? endDate
            if row.startedAt >= limit { return false }
        }
        if let endReason, row.endReason != endReason { return false }
        return dataKind.matches(isDemo: row.isDemo)
    }
}
