@testable import ProjectZD8

/// 認証モデルテストで車両データ削除境界を再現します。
@MainActor
final class AuthenticationModelVehicleDataEraserFake: AccountVehicleDataErasurePort {
    /// 全削除されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// 車両カタログ全削除を記録します。
    ///
    /// 責務: 1件のアカウント識別子を車両データ削除履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAllVehicleData(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }

    /// このテストでは端末キャッシュに車両を保持しません。
    ///
    /// 責務: テスト対象外のローカル車両ID照会へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func localVehicleIDs(for accountIdentifier: String) -> [VehicleID] { [] }

    /// このテストでは端末キャッシュ単独削除を使用しません。
    ///
    /// 責務: テスト対象外の車両キャッシュ削除要求を副作用なしで満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func removeLocalVehicleCache(for accountIdentifier: String) {}
}
