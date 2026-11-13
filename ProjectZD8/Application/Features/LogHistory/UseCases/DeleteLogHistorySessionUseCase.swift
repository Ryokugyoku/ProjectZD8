import Foundation

/// セッションを、記録中でないことを確かめてから削除します。
nonisolated struct DeleteLogHistorySessionUseCase: Sendable {
    private let sessions: any SessionRepository

    /// 責務: 削除に使う永続化契約を固定します。
    init(sessions: any SessionRepository) {
        self.sessions = sessions
    }

    /// セッションを取得条件・サンプルごと削除します。
    ///
    /// 責務: 最新の状態で記録中でないことを確認して削除します。
    /// - Parameter id: 削除するセッションのID。
    /// - Throws: `LogHistoryFailure.sessionNotFound` / `.deleteRefusedWhileRecording` / `.deleteFailed`。
    func execute(_ id: SessionID) async throws {
        do {
            guard let session = try await sessions.session(id) else { throw LogHistoryFailure.sessionNotFound }
            guard !session.isRecording else { throw LogHistoryFailure.deleteRefusedWhileRecording }
            try await sessions.delete(id)
        } catch let failure as LogHistoryFailure {
            throw failure
        } catch {
            throw LogHistoryFailure.deleteFailed
        }
    }
}
