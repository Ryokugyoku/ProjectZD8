import Foundation
@testable import ProjectZD8

/// 保存された接続セッションを順に記録し、指定時だけ保存を失敗させる Repository の spy です。
@MainActor
final class SavingConnectionSessionRepositorySpy: ConnectionSessionRepository {
    /// 保存に成功したセッションを保存順に記録します。
    private(set) var saved: [ConnectionSession] = []

    /// `true` の場合は保存を失敗させます。
    var failsSave = false

    /// 保存に成功するたびに呼ぶ処理です。手順の順序を記録するために使います。
    var saveDidSucceed: (@MainActor (ConnectionSession) -> Void)?

    /// セッションを記録します。
    ///
    /// 責務: 保存要求を記録して通知し、指定時だけ失敗させます。
    /// - Parameter session: 保存するセッション。
    /// - Throws: `failsSave` の場合は `ConnectionSessionRepositoryError.unavailable`。
    func save(_ session: ConnectionSession) throws {
        if failsSave { throw ConnectionSessionRepositoryError.unavailable }
        saved.append(session)
        saveDidSucceed?(session)
    }

    /// 保存済みの未終了セッションは無いものとして空を返します。
    ///
    /// 責務: アカウント有効化時の回復処理を発生させない照会結果を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 常に空配列。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] { [] }
}
