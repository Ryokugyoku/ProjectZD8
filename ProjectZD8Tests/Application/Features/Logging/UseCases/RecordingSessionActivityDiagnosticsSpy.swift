@testable import ProjectZD8

/// 記録中表示の診断境界の偽物です。失敗した操作の種類を記録します。
@MainActor
final class RecordingSessionActivityDiagnosticsSpy: RecordingSessionActivityDiagnosticsPort {
    /// 記録された失敗操作を受け取った順に持ちます。
    private(set) var failedOperations: [RecordingSessionActivityOperation] = []

    /// 失敗を記録します。
    ///
    /// 責務: 操作の種類だけを残します。
    func operationFailed(_ operation: RecordingSessionActivityOperation, error: any Error) {
        failedOperations.append(operation)
    }
}
