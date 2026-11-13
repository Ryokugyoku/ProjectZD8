import Foundation

/// 終了済みセッションを、車両ごとに絞り込み・並び替えてまとめます。
nonisolated struct BuildLogHistoryGroupsUseCase: Sendable {
    /// 責務: 依存の無い純粋な集約です。
    init() {}

    /// セッションを車両別のグループへまとめます。
    ///
    /// 責務: 絞り込みを適用し、車両ごとに並び順を適用し、最新のセッションを持つ車両から並べます。
    /// - Parameters:
    ///   - rows: 終了済みセッションの行。
    ///   - vehicleNames: 車両IDごとの車両名。
    ///   - filter: 絞り込み条件。
    ///   - sortOrder: 並び順。
    ///   - calendar: 日付境界に使うカレンダー。
    /// - Returns: 条件に合うセッションを持つ車両のグループ。
    func execute(
        rows: [LogHistorySessionRow],
        vehicleNames: [VehicleID: String],
        filter: LogHistoryFilter,
        sortOrder: LogHistorySortOrder,
        calendar: Calendar = .current
    ) -> [LogHistoryVehicleGroup] {
        Dictionary(grouping: rows.filter { filter.matches($0, calendar: calendar) }, by: \.vehicleID)
            .map { vehicleID, sessions in
                LogHistoryVehicleGroup(
                    id: vehicleID,
                    vehicleName: vehicleNames[vehicleID],
                    sessions: sessions.sorted(by: sortOrder.areInIncreasingOrder)
                )
            }
            .sorted { ($0.latestStartedAt ?? .distantPast) > ($1.latestStartedAt ?? .distantPast) }
    }
}
