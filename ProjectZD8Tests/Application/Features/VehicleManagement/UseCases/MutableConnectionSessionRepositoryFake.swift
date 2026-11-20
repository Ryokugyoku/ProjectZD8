import Foundation
@testable import ProjectZD8

/// 保存済みセッションを保存・終了の操作で差し替えられる接続セッション Repository の fake です。
final class MutableConnectionSessionRepositoryFake: ConnectionSessionRepository {
    /// 保持しているセッションです(保存順)。
    private(set) var storedSessions: [ConnectionSession] = []

    /// 空の保存状態で生成します。
    ///
    /// 責務: セッションを1件も持たない fake を作ります。
    init() {}

    /// セッションを同じIDの置き換えか末尾への追加として保存します。
    ///
    /// 責務: 1件のセッションの現在内容を保持します。
    /// - Parameter session: 保存するセッション。
    func save(_ session: ConnectionSession) throws {
        if let index = storedSessions.firstIndex(where: { $0.id == session.id }) {
            storedSessions[index] = session
        } else {
            storedSessions.append(session)
        }
    }

    /// 指定アカウントのセッションを返します。
    ///
    /// 責務: 保持中のセッションのうち、指定アカウントのものだけを返します。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: そのアカウントのセッション。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        storedSessions.filter { $0.accountIdentifier == accountIdentifier }
    }

    /// 指定セッションを終了済みにして保持し直します。
    ///
    /// 責務: 終了日時と終了理由を設定した状態へ、保存済みの1件を更新します。
    /// - Parameters:
    ///   - id: 終了するセッションのID。
    ///   - reason: 終了理由。
    func end(sessionID id: ConnectionSessionID, reason: ConnectionSessionEndReason) {
        guard let index = storedSessions.firstIndex(where: { $0.id == id }) else { return }
        storedSessions[index].endedAt = storedSessions[index].startedAt.addingTimeInterval(60)
        storedSessions[index].endReason = reason
    }
}
