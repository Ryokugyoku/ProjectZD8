@testable import ProjectZD8

/// 記録中表示の状態遷移の診断ポートへ伝えられた出来事を順に記録する spy です。
@MainActor
final class RecordingSessionActivityLifecycleDiagnosticsSpy: RecordingSessionActivityLifecycleDiagnosticsPort {
    /// 診断ポートへ伝えられた1件の出来事です。
    enum Event: Equatable {
        /// 表示を開始できた。
        case started
        /// アプリが表示を終了した。
        case ended
        /// システムまたはユーザーに表示を閉じられた。
        case closedBySystem
        /// 停止要求を受け付けた。
        case stopRequestAccepted
        /// 停止要求を断った。
        case stopRequestDeclined
    }

    /// 伝えられた出来事です。
    private(set) var events: [Event] = []

    /// 責務: 表示開始を記録します。
    func activityStarted() {
        events.append(.started)
    }

    /// 責務: アプリによる表示終了を記録します。
    func activityEnded() {
        events.append(.ended)
    }

    /// 責務: アプリ以外による表示終了を記録します。
    func activityClosedBySystem() {
        events.append(.closedBySystem)
    }

    /// 責務: 受け付けた停止要求を記録します。
    func stopRequestAccepted() {
        events.append(.stopRequestAccepted)
    }

    /// 責務: 断った停止要求を記録します。
    func stopRequestDeclined() {
        events.append(.stopRequestDeclined)
    }
}
