import Foundation

/// 記録中の常時表示が、1回の記録セッションの間だけ保持する情報です。
nonisolated struct RecordingSessionActivitySession: Equatable, Sendable {
    /// 記録を開始した時刻です。
    let startedAt: Date
    /// 写真と車両名を確定した車両のIDです。未登録なら `nil` です。
    var vehicleID: VehicleID?
    /// `vehicleID` を一度でも確定したかどうかです(未登録の `nil` と未確定を区別します)。
    var hasResolvedVehicle = false
    /// 表示用に保存した車両写真のファイル名です。写真なしなら `nil` です。
    var photoFileName: String?

    /// 開始時刻だけを持つ未確定のセッション情報を生成します。
    ///
    /// 責務: 車両未確定・写真なしの状態から始めます。
    /// - Parameter startedAt: 記録を開始した時刻。
    init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
