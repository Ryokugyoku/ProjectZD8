import Foundation

/// 全セッションを車両ごとの記録活動へ集計します。
nonisolated struct LoadVehicleActivitySummariesUseCase: Sendable {
    private let sessions: any SessionRepository

    /// 責務: セッション取得先を固定します。
    init(sessions: any SessionRepository) {
        self.sessions = sessions
    }

    /// 全セッションを車両IDごとの集計へ変換します。
    ///
    /// 責務: セッション一覧を1回走査して車両別のセッション件数・時間・中断数・走行距離計を求めます。
    /// - Returns: 車両IDをキーとした集計。セッションの無い車両は含みません。
    /// - Throws: セッションを読み込めない場合の永続化エラー。
    func execute() async throws -> [VehicleID: VehicleActivitySummary] {
        var summaries: [VehicleID: VehicleActivitySummary] = [:]
        var odometerDates: [VehicleID: Date] = [:]
        for session in try await sessions.sessions(for: nil) {
            let previous = summaries[session.vehicleID] ?? VehicleActivitySummary()
            let sessionDate = session.endedAt ?? session.startedAt
            var odometer = previous.latestOdometerKilometers
            if let value = session.odometerEndKilometers ?? session.odometerStartKilometers,
               sessionDate >= (odometerDates[session.vehicleID] ?? .distantPast) {
                odometerDates[session.vehicleID] = sessionDate
                odometer = value
            }
            summaries[session.vehicleID] = VehicleActivitySummary(
                sessionCount: previous.sessionCount + 1,
                lastLoggedAt: max(previous.lastLoggedAt ?? .distantPast, sessionDate),
                totalRecordedDuration: previous.totalRecordedDuration + max(0, session.duration ?? 0),
                interruptedCount: previous.interruptedCount + (session.wasInterrupted ? 1 : 0),
                isRecording: previous.isRecording || session.isRecording,
                latestOdometerKilometers: odometer
            )
        }
        return summaries
    }
}
