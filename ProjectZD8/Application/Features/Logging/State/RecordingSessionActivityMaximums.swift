/// 記録セッション中に観測した、項目ごとの最大値です。終了表示に載せます。
nonisolated struct RecordingSessionActivityMaximums: Equatable, Codable, Sendable {
    /// 車速(km/h)の最大値です。
    var vehicleSpeed: RecordingSessionActivityMetric = .unavailable
    /// エンジン回転数(rpm)の最大値です。
    var engineSpeed: RecordingSessionActivityMetric = .unavailable
    /// スロットル開度(%)の最大値です。
    var throttlePosition: RecordingSessionActivityMetric = .unavailable
}
