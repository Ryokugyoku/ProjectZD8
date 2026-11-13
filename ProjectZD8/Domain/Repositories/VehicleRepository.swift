/// 登録車両をアカウントスコープ内で読み書きする能力です。
@MainActor
protocol VehicleRepository {
    /// 指定アカウントの登録車両を読み込みます。
    ///
    /// 責務: 1件のアカウントに属する現在の車両一覧を返します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 更新日時の新しい順に並ぶ登録車両。
    func loadVehicles(for accountIdentifier: String) async throws -> [VehicleProfile]

    /// 指定アカウントへ車両プロフィールを保存します。
    ///
    /// 責務: 1件の車両プロフィールを同じアカウントスコープへ作成または更新します。
    /// - Parameters:
    ///   - vehicle: 保存する車両プロフィール。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    func saveVehicle(_ vehicle: VehicleProfile, for accountIdentifier: String) async throws

    /// 指定アカウントから車両プロフィールを削除します。
    ///
    /// 責務: 1件のアカウントスコープから指定車両だけを削除します。
    /// - Parameters:
    ///   - id: 削除する車両ID。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    func deleteVehicle(id: VehicleID, for accountIdentifier: String) async throws
}
