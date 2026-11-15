/// 記録の調停役と車両照合のテストで注入する失敗です。
nonisolated enum VehicleRecordingTestError: Error, Equatable {
    /// 登録済み車両の読込に失敗しました。
    case vehicleLoadFailed

    /// 車両の保存に失敗しました。
    case vehicleSaveFailed
    /// 観測VINセッションへの紐付けに失敗しました。
    case sessionAssignmentFailed
}
