/// 接続時点の車両表示情報を履歴へ保持します。
struct ConnectionSessionVehicle: Equatable, Codable, Sendable {
    /// 登録車両の安定識別子です。
    let id: VehicleID
    /// 接続時点でのユーザー編集可能な車両名称です。
    let name: String
    /// 接続時点でのVINまたはOBD由来代表識別値です。
    let displayIdentifier: String

    /// 登録車両から履歴用の不変スナップショットを生成します。
    ///
    /// 責務: 1台の登録車両を接続履歴に必要な表示情報へ縮約します。
    /// - Parameter profile: 接続対象として確定した登録車両。
    init(profile: VehicleProfile) {
        id = profile.id
        name = profile.name
        displayIdentifier = profile.displayIdentifier
    }

    /// 永続化済みの表示情報からスナップショットを復元します。
    ///
    /// 責務: 保存済みの車両IDと表示値を1件の履歴用車両情報へまとめます。
    /// - Parameters:
    ///   - id: 登録車両の安定識別子。
    ///   - name: 接続時点の車両名称。
    ///   - displayIdentifier: 接続時点の車両代表識別値。
    init(id: VehicleID, name: String, displayIdentifier: String) {
        self.id = id
        self.name = name
        self.displayIdentifier = displayIdentifier
    }
}
