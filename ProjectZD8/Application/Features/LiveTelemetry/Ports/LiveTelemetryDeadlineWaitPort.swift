/// 一時停止中の猶予切れを検知するため、単調時計上の期限まで待つ能力です。
///
/// 要求と要求の間に待機を挟まない方針の例外として、一時停止中の猶予切れの期限待ちだけに使います。
/// 経過の判定は呼び出し側が単調時計で行うため、待ちが早く返っても遅く返っても判定は変わりません。
nonisolated protocol LiveTelemetryDeadlineWaitPort: Sendable {
    /// 単調時計が指定値に達するまで待ちます。
    ///
    /// 責務: 期限まで呼び出し元を待たせ、期限到達または取消で返ります。
    /// - Parameter deadlineNanoseconds: 待ち終える単調時計の値(`MonotonicClockPort` と同じ基準)。
    /// - Throws: 取消された場合は `CancellationError`。
    func wait(untilNanoseconds deadlineNanoseconds: UInt64) async throws
}
