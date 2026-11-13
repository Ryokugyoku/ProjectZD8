import Foundation

/// セッション選択の候補です。
nonisolated struct AnalysisSessionOption: Identifiable, Equatable, Sendable {
    let id: SessionID
    let vehicleID: VehicleID
    let startedAt: Date
    /// 記録時間(秒)です。記録中は `nil` です。
    let durationSeconds: Double?
    let sampleCount: Int
    let isDemo: Bool
    let rawAvailability: RawAvailability

    /// 責務: セッションから選択候補を生成します。
    init(_ session: DriveSession) {
        id = session.id
        vehicleID = session.vehicleID
        startedAt = session.startedAt
        durationSeconds = session.duration
        sampleCount = session.sampleCount
        isDemo = session.isDemo
        rawAvailability = session.rawAvailability
    }
}
