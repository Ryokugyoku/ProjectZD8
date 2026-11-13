import Foundation

/// 1台の車両に属する終了済みセッションの集まりと合計です。
nonisolated struct LogHistoryVehicleGroup: Identifiable, Equatable, Sendable {
    let id: VehicleID
    /// 車両名です。車両情報が見つからなければ `nil` です。
    let vehicleName: String?
    /// 絞り込みと並び順を適用したセッションです。
    let sessions: [LogHistorySessionRow]

    var sessionCount: Int { sessions.count }
    /// ユーザー操作以外で終了したセッション数です。
    var interruptedCount: Int { sessions.filter(\.wasInterrupted).count }
    /// 記録時間の合計(秒)です。
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + ($1.duration ?? 0) } }
    /// 全セッションの距離が分かる場合だけの距離合計(km)です。
    var totalDistanceKilometers: Double? {
        let distances = sessions.compactMap(\.distanceKilometers)
        guard !sessions.isEmpty, distances.count == sessions.count else { return nil }
        return distances.reduce(0, +)
    }
    /// グループ内で最も新しい開始日時です。
    var latestStartedAt: Date? { sessions.map(\.startedAt).max() }
    var totalDurationText: String { LogHistorySessionRow.durationText(totalDuration) }
    var totalDistanceText: String? { totalDistanceKilometers.map(LogHistorySessionRow.distanceText) }
}
