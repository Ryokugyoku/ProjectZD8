import Foundation

/// アップロード済みの終了済みセッションについて、この端末のRawを手動で解放します。
nonisolated struct FreeUpSessionSpaceUseCase: Sendable {
    private let sessions: any SessionRepository

    /// 責務: 解放に使う永続化契約を固定します。
    init(sessions: any SessionRepository) {
        self.sessions = sessions
    }

    /// この端末のサンプルを解放します。
    ///
    /// 責務: 最新の状態で解放できることを確認し、`evictSamples` を呼びます。
    /// - Parameter id: 解放するセッションのID。
    /// - Throws: `LogHistoryFailure.sessionNotFound` / `.freeUpSpaceNotAllowed` / `.freeUpSpaceFailed`。
    func execute(_ id: SessionID) async throws {
        do {
            guard let session = try await sessions.session(id) else { throw LogHistoryFailure.sessionNotFound }
            guard LogHistorySessionRow(session: session).canFreeUpSpace else { throw LogHistoryFailure.freeUpSpaceNotAllowed }
            try await sessions.evictSamples(for: id)
        } catch let failure as LogHistoryFailure {
            throw failure
        } catch StoreError.invalidState {
            throw LogHistoryFailure.freeUpSpaceNotAllowed
        } catch {
            throw LogHistoryFailure.freeUpSpaceFailed
        }
    }
}
