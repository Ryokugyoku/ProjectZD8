import Foundation

/// 履歴一覧の1セッション分です。
nonisolated struct LogHistorySessionRow: Identifiable, Equatable, Sendable {
    let id: SessionID
    let vehicleID: VehicleID
    let startedAt: Date
    /// 終了日時です。記録中は `nil` です。
    let endedAt: Date?
    /// 記録時間(秒)です。記録中は `nil` です。
    let duration: TimeInterval?
    /// 走行距離(km)です。距離計から求められなければ `nil` です。
    let distanceKilometers: Double?
    let endReason: SessionEndReason?
    /// 終了理由の表示名キーです。記録中は `nil` です。
    let endReasonKey: String?
    let isRecording: Bool
    /// ユーザー操作以外で終了したかどうかです。
    let wasInterrupted: Bool
    let isDemo: Bool
    let sampleCount: Int
    let rawLocation: LogHistoryRawLocation
    let uploadState: LogHistoryUploadState
    /// 手動で「この端末の領域を解放」できるかどうかです。
    let canFreeUpSpace: Bool

    /// 保存済みのセッションから行を生成します。
    ///
    /// 責務: セッションを一覧表示用の値へ写し、Rawの所在とアップロード状態を `archiveDigest` から導きます。
    init(session: DriveSession) {
        id = session.id
        vehicleID = session.vehicleID
        startedAt = session.startedAt
        endedAt = session.endedAt
        duration = session.duration.map { max(0, $0) }
        distanceKilometers = session.recordedDistanceKilometers
        endReason = session.endReason
        endReasonKey = session.endReason.map { "history.reason.\($0.rawValue)" }
        isRecording = session.isRecording
        wasInterrupted = session.wasInterrupted
        isDemo = session.isDemo
        sampleCount = session.sampleCount
        rawLocation = LogHistoryRawLocation(session.rawAvailability)
        uploadState = session.archiveDigest == nil ? .notUploaded : .uploaded
        canFreeUpSpace = !session.isRecording && session.archiveDigest != nil && session.rawAvailability == .local
    }

    /// 記録時間の表示用文字列です。記録中は `nil` です。
    var durationText: String? { duration.map(Self.durationText) }

    /// 走行距離の表示用文字列です。距離が無ければ `nil` です。
    var distanceText: String? { distanceKilometers.map(Self.distanceText) }

    /// 責務: 秒数を表示用の時間文字列へ変換します。
    static func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(0, seconds).rounded()))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }

    /// 責務: キロメートルを表示用の距離文字列へ変換します。
    static func distanceText(_ kilometers: Double) -> String {
        Measurement(value: kilometers, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
