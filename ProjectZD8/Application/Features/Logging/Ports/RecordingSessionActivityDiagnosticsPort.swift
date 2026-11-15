/// 記録中表示の失敗を診断記録へ残すための狭い境界です。
///
/// 表示の失敗は記録処理へ波及させず、この境界へだけ渡します。
@MainActor
protocol RecordingSessionActivityDiagnosticsPort: AnyObject {
    /// 記録中表示の操作に失敗したことを記録します。
    ///
    /// 責務: 1件の失敗した操作とエラーを診断記録へ渡します。
    /// - Parameters:
    ///   - operation: 失敗した操作。
    ///   - error: 発生したエラー。
    func operationFailed(_ operation: RecordingSessionActivityOperation, error: any Error)
}
