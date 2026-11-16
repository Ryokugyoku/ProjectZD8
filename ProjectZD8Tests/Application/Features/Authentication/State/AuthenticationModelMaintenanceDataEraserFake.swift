@testable import ProjectZD8

/// 認証モデル・削除ユースケースのテストで、整備のクラウド削除を記録して受け流すFakeです。
@MainActor
final class AuthenticationModelMaintenanceDataEraserFake: AccountMaintenanceDataErasurePort {
    /// 整備のクラウド削除を要求されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// 整備のクラウド削除要求を記録します。
    ///
    /// 責務: 1件の整備クラウド削除を検査可能な履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllMaintenanceData(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }
}
