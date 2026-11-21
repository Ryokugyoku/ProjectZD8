import Foundation
@testable import ProjectZD8

/// 走行ルートの即時送信の診断を、呼ばれた順に記録する Spy です。
nonisolated final class ConnectionSessionLocationTrackSyncDiagnosticsSpy: ConnectionSessionLocationTrackSyncDiagnosticsPort,
    @unchecked Sendable {
    /// 記録する診断です。
    nonisolated enum Event: Equatable, Sendable {
        /// 即時送信の失敗です。
        case failed(errorDomain: String, errorCode: Int)
        /// 即時送信の成功です。
        case succeeded(uploadedCount: Int)
    }

    /// 記録を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、呼ばれた順の診断です。
    private var storedEvents: [Event] = []

    /// 空の Spy を生成します。
    ///
    /// 責務: 何も記録していない状態を構築します。
    init() {}

    /// 呼ばれた順の診断です。
    var events: [Event] {
        lock.withLock { storedEvents }
    }

    /// 即時送信の失敗を記録します。
    ///
    /// 責務: エラーの domain と code を記録の末尾へ追加します。
    /// - Parameters:
    ///   - errorDomain: エラーの domain。
    ///   - errorCode: エラーの code。
    func immediateUploadFailed(errorDomain: String, errorCode: Int) {
        lock.withLock { storedEvents.append(.failed(errorDomain: errorDomain, errorCode: errorCode)) }
    }

    /// 即時送信の成功を記録します。
    ///
    /// 責務: 送信した件数を記録の末尾へ追加します。
    /// - Parameter uploadedCount: 送信したセッションの件数。
    func immediateUploadSucceeded(uploadedCount: Int) {
        lock.withLock { storedEvents.append(.succeeded(uploadedCount: uploadedCount)) }
    }
}
