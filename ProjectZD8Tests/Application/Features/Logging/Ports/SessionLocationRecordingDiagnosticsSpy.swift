import Foundation
@testable import ProjectZD8

/// 位置記録の診断境界の spy です。どのスレッドから呼ばれても、ロックで保護して受け取った順に記録します。
nonisolated final class SessionLocationRecordingDiagnosticsSpy: SessionLocationRecordingDiagnosticsPort, @unchecked Sendable {
    /// 状態変化の保存失敗の記録です。
    struct EventFailure: Equatable {
        /// 保存できなかった状態の種類。
        let kind: ConnectionSessionLocationEventKind
        /// 保存先の接続セッション。
        let sessionID: ConnectionSessionID
    }

    /// 記録を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、位置の保存に失敗したセッションです(受信順)。
    private var storedSampleFailures: [ConnectionSessionID] = []
    /// ロックで保護した、状態変化の保存失敗です(受信順)。
    private var storedEventFailures: [EventFailure] = []

    /// 記録が空の spy を生成します。
    ///
    /// 責務: 失敗を1件も受け取っていない状態を構築します。
    init() {}

    /// 位置の保存に失敗したセッションです(受信順)。
    var sampleFailures: [ConnectionSessionID] {
        lock.withLock { storedSampleFailures }
    }

    /// 状態変化の保存失敗です(受信順)。
    var eventFailures: [EventFailure] {
        lock.withLock { storedEventFailures }
    }

    /// 位置の保存失敗を記録します。
    ///
    /// 責務: 失敗したセッションを受信順に残します。
    /// - Parameters:
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗(記録しません)。
    func sampleStorageFailed(sessionID: ConnectionSessionID, error _: any Error) {
        lock.withLock { storedSampleFailures.append(sessionID) }
    }

    /// 状態変化の保存失敗を記録します。
    ///
    /// 責務: 失敗した種類とセッションを受信順に残します。
    /// - Parameters:
    ///   - kind: 保存できなかった状態の種類。
    ///   - sessionID: 保存先の接続セッション。
    ///   - error: 保存の失敗(記録しません)。
    func eventStorageFailed(_ kind: ConnectionSessionLocationEventKind, sessionID: ConnectionSessionID, error _: any Error) {
        lock.withLock { storedEventFailures.append(EventFailure(kind: kind, sessionID: sessionID)) }
    }
}
