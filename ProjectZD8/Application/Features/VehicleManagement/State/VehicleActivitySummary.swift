import Foundation

/// 1台の車両の記録活動をまとめた集計です。
nonisolated struct VehicleActivitySummary: Equatable, Sendable {
    /// 記録済みセッション件数です(記録中を含む)。
    let sessionCount: Int
    /// 最後にログを記録した日時です。ログが無ければ `nil` です。
    let lastLoggedAt: Date?
    /// 終了済みセッションの記録時間の合計(秒)です。
    let totalRecordedDuration: TimeInterval
    /// ユーザー操作以外で終了したセッションの件数です。
    let interruptedCount: Int
    /// 現在記録中のセッションがあるかどうかです。
    let isRecording: Bool
    /// 最新セッションで分かっている走行距離計の値(km)です。
    let latestOdometerKilometers: Double?

    /// 記録が無い車両の集計を生成します。
    ///
    /// 責務: 集計値を明示してまとめます。
    init(
        sessionCount: Int = 0,
        lastLoggedAt: Date? = nil,
        totalRecordedDuration: TimeInterval = 0,
        interruptedCount: Int = 0,
        isRecording: Bool = false,
        latestOdometerKilometers: Double? = nil
    ) {
        self.sessionCount = sessionCount
        self.lastLoggedAt = lastLoggedAt
        self.totalRecordedDuration = totalRecordedDuration
        self.interruptedCount = interruptedCount
        self.isRecording = isRecording
        self.latestOdometerKilometers = latestOdometerKilometers
    }

    /// 総記録時間の表示用文字列です(例: 1h 5m)。
    var totalRecordedDurationText: String {
        Duration.seconds(Int(max(0, totalRecordedDuration).rounded()))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }

    /// 走行距離計の表示用文字列です。値が無ければ `nil` です。
    var latestOdometerText: String? {
        latestOdometerKilometers.map {
            Measurement(value: $0, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
    }
}
