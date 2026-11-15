/// 記録中表示のテストで、境界の失敗を表す任意のエラーです。
struct RecordingSessionActivityTestError: Error, Equatable {
    /// 失敗の区別に使う名前です。
    let label: String
}
