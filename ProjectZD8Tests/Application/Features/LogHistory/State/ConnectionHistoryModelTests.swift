import Foundation
import XCTest
@testable import ProjectZD8

/// アカウント単位の接続履歴表示状態を検証します。
@MainActor
final class ConnectionHistoryModelTests: XCTestCase {
    /// 有効化したアカウントの履歴だけを新しい順で公開します。
    ///
    /// 責務: 1件のアカウント変更が対応する履歴一覧へ変換されることを確認します。
    func testAccountActivationLoadsScopedSessions() {
        let older = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 10))
        let newer = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 20))
        let repository = FixedConnectionSessionRepository(sessions: [newer, older])
        let model = ConnectionHistoryModel(repository: repository)

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(model.state.phase, .loaded)
        XCTAssertEqual(model.state.sessions.map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.state.connectedCount, 2)
    }
}

/// テスト用の固定接続履歴を返します。
private struct FixedConnectionSessionRepository: ConnectionSessionRepository {
    /// 取得要求へ返す固定セッション一覧です。
    let sessions: [ConnectionSession]

    /// この読込専用テスト実装では保存を行いません。
    ///
    /// 責務: 保存要求を副作用なしで受理します。
    /// - Parameter session: 使用しない接続セッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッションから指定アカウント分を返します。
    ///
    /// 責務: 固定履歴を1件のアカウント識別子で絞り込みます。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: 指定アカウントに属する固定履歴。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        sessions.filter { $0.accountIdentifier == accountIdentifier }
    }
}
