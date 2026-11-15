/// 取得記録を受け付けられなかった理由です。
nonisolated enum LiveTelemetryAcquisitionRecordingError: Error, Equatable, Sendable {
    /// 記録が現在の取得世代に属していないか、開始が完了していません。
    case inactiveGeneration
    /// 周回・要求の順序または要求内容が開始済みの記録と一致しません。
    case invalidInput
    /// 保存も欠損の記録もできず、取得を続けられません。
    case storageFailed
}
