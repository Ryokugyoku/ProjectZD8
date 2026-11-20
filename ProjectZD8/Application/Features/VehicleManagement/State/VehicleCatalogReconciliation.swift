/// 画面保持中の車両一覧と読込結果を更新日時で突合した同期方針です。
struct VehicleCatalogReconciliation: Equatable {
    /// 画面へ反映する、更新日時の新しい順の車両一覧です。
    let merged: [VehicleProfile]
    /// 読込結果より新しいか読込結果にないため、保存先へ反映し直す車両です。
    let uploadTargets: [VehicleProfile]

    /// ローカル一覧と読込結果から同期方針を作成します。
    ///
    /// 責務: 同じIDの車両は更新日時の新しい方を採用し、ローカル側を採用したものと読込結果にないものをアップロード対象にします。
    /// - Parameters:
    ///   - local: 画面保持中の車両一覧。
    ///   - remote: リポジトリ読込時点の車両一覧。
    init(local: [VehicleProfile], remote: [VehicleProfile]) {
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var merged: [VehicleProfile] = []
        var uploadTargets: [VehicleProfile] = []
        var syncedIDs: Set<VehicleID> = []

        for localVehicle in local {
            guard let remoteVehicle = remoteByID[localVehicle.id] else {
                merged.append(localVehicle)
                uploadTargets.append(localVehicle)
                continue
            }
            syncedIDs.insert(localVehicle.id)
            if localVehicle.updatedAt > remoteVehicle.updatedAt {
                merged.append(localVehicle)
                uploadTargets.append(localVehicle)
            } else {
                merged.append(remoteVehicle)
            }
        }

        for remoteVehicle in remote where !syncedIDs.contains(remoteVehicle.id) {
            merged.append(remoteVehicle)
        }

        self.merged = merged.sorted { $0.updatedAt > $1.updatedAt }
        self.uploadTargets = uploadTargets
    }
}
