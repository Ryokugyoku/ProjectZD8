import Foundation

/// 整備編集画面の未保存入力と、その編集規則です。
nonisolated struct MaintenanceDraft: Equatable, Sendable {
    /// 編集元の記録IDです。新規は `nil` です。
    let recordID: MaintenanceRecordID?
    /// 必ず関連付ける車両のIDです。
    let vehicleID: VehicleID
    /// 軽整備または重整備の区分です。作成後は変えられません。
    let kind: MaintenanceKind
    var title: String
    var performedAt: Date
    var odometerKilometers: Double?
    var notes: String
    var workItems: [MaintenanceWorkItem]
    var photos: [MaintenancePhoto]
    var fastenerGroups: [MaintenanceFastenerGroup]
    /// 編集元の作成日時です。
    let createdAt: Date

    /// 新規の入力を既定の作業項目付きで生成します。
    ///
    /// 責務: 区分に応じた作業項目を1件持つ空の入力を作ります。
    init(vehicleID: VehicleID, kind: MaintenanceKind, now: Date) {
        recordID = nil
        self.vehicleID = vehicleID
        self.kind = kind
        title = ""
        performedAt = now
        odometerKilometers = nil
        notes = ""
        workItems = [Self.defaultWorkItem(for: kind)]
        photos = []
        fastenerGroups = []
        createdAt = now
    }

    /// 保存済みの記録から入力を生成します。
    ///
    /// 責務: 記録の全内容を編集可能な入力へ写します。
    init(record: MaintenanceRecord) {
        recordID = record.id
        vehicleID = record.vehicleID
        kind = record.kind
        title = record.title
        performedAt = record.performedAt
        odometerKilometers = record.odometerKilometers
        notes = record.notes
        workItems = record.workItems
        photos = record.photos
        fastenerGroups = record.fastenerGroups
        createdAt = record.createdAt
    }

    /// 区分ごとの既定の作業項目です。
    private static func defaultWorkItem(for kind: MaintenanceKind) -> MaintenanceWorkItem {
        MaintenanceWorkItem(
            component: kind == .light ? .engineOil : .engineAssembly,
            operation: kind == .light ? .replacement : .inspection
        )
    }

    // MARK: - Editing rules

    /// 責務: 区分に応じた既定の作業項目を1件追加します。
    mutating func addWorkItem() {
        workItems.append(Self.defaultWorkItem(for: kind))
    }

    /// 責務: 作業項目を削除します。
    mutating func removeWorkItem(_ id: UUID) {
        workItems.removeAll { $0.id == id }
    }

    /// 責務: 重整備にだけ、空の締結グループを1件追加します。
    mutating func addFastenerGroup() {
        guard kind == .heavy else { return }
        fastenerGroups.append(MaintenanceFastenerGroup(name: ""))
    }

    /// 責務: 締結グループを削除します。
    mutating func removeFastenerGroup(_ id: UUID) {
        fastenerGroups.removeAll { $0.id == id }
    }

    /// 責務: 締結グループへ、位置が空の個別締結証跡を1件追加します。
    mutating func addFastener(to groupID: UUID) {
        guard let group = fastenerGroups.firstIndex(where: { $0.id == groupID }) else { return }
        fastenerGroups[group].installations.append(FastenerInstallationEvidence(position: ""))
    }

    /// 責務: 個別締結証跡を削除します。
    mutating func removeFastener(groupID: UUID, evidenceID: UUID) {
        guard let group = fastenerGroups.firstIndex(where: { $0.id == groupID }) else { return }
        fastenerGroups[group].installations.removeAll { $0.id == evidenceID }
    }

    /// 責務: 個別締結証跡へ締結完了日時を記録します。
    mutating func confirmFastener(groupID: UUID, evidenceID: UUID, at date: Date) {
        guard let (group, evidence) = locate(groupID: groupID, evidenceID: evidenceID) else { return }
        fastenerGroups[group].installations[evidence].tightenedAt = date
    }

    /// 責務: 登録済みの写真を個別締結証跡へ重複なく関連付けます。
    mutating func linkPhoto(_ photoID: PhotoID, groupID: UUID, evidenceID: UUID) {
        guard photos.contains(where: { $0.id == photoID }),
              let (group, evidence) = locate(groupID: groupID, evidenceID: evidenceID),
              !fastenerGroups[group].installations[evidence].photoIDs.contains(photoID) else { return }
        fastenerGroups[group].installations[evidence].photoIDs.append(photoID)
    }

    /// 責務: 個別締結証跡から写真の関連付けを外します。
    mutating func unlinkPhoto(_ photoID: PhotoID, groupID: UUID, evidenceID: UUID) {
        guard let (group, evidence) = locate(groupID: groupID, evidenceID: evidenceID) else { return }
        fastenerGroups[group].installations[evidence].photoIDs.removeAll { $0 == photoID }
    }

    /// 責務: 登録済みの写真を締結グループの分解状態の写真へ重複なく関連付けます。
    mutating func linkRemovalPhoto(_ photoID: PhotoID, groupID: UUID) {
        guard photos.contains(where: { $0.id == photoID }),
              let group = fastenerGroups.firstIndex(where: { $0.id == groupID }),
              !fastenerGroups[group].removalPhotoIDs.contains(photoID) else { return }
        fastenerGroups[group].removalPhotoIDs.append(photoID)
    }

    /// 責務: 締結グループの分解状態の写真から関連付けを外します。
    mutating func unlinkRemovalPhoto(_ photoID: PhotoID, groupID: UUID) {
        guard let group = fastenerGroups.firstIndex(where: { $0.id == groupID }) else { return }
        fastenerGroups[group].removalPhotoIDs.removeAll { $0 == photoID }
    }

    /// 責務: 写真を入力へ追加します。
    mutating func addPhoto(_ photo: MaintenancePhoto) {
        photos.append(photo)
    }

    /// 責務: 写真を入力から外し、全ての締結証跡からの関連付けも外します。
    mutating func removePhoto(_ id: PhotoID) {
        photos.removeAll { $0.id == id }
        for group in fastenerGroups.indices {
            fastenerGroups[group].removalPhotoIDs.removeAll { $0 == id }
            for evidence in fastenerGroups[group].installations.indices {
                fastenerGroups[group].installations[evidence].photoIDs.removeAll { $0 == id }
            }
        }
    }

    /// 責務: 写真の説明を更新します。
    mutating func setCaption(_ caption: String, for id: PhotoID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].caption = caption
    }

    /// 締結グループと個別証跡の配列位置を返します。
    private func locate(groupID: UUID, evidenceID: UUID) -> (Int, Int)? {
        guard let group = fastenerGroups.firstIndex(where: { $0.id == groupID }),
              let evidence = fastenerGroups[group].installations.firstIndex(where: { $0.id == evidenceID }) else { return nil }
        return (group, evidence)
    }

    // MARK: - Validation

    /// 入力を検証します。
    ///
    /// 責務: 保存できない入力を問題の一覧として返します。
    /// - Returns: 問題の一覧。空なら保存できます。
    func issues() -> [MaintenanceDraftIssue] {
        var result: [MaintenanceDraftIssue] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.titleRequired) }
        if workItems.isEmpty { result.append(.workItemRequired) }
        if let odometer = odometerKilometers, !(odometer >= 0 && odometer.isFinite) { result.append(.odometerInvalid) }
        guard kind == .heavy else { return result }
        for group in fastenerGroups {
            if group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.fastenerGroupNameRequired(group.id))
            }
            let hasNegative = group.removedCount < 0
                || (group.expectedCount ?? 0) < 0
                || group.installations.contains { ($0.torqueNewtonMeters ?? 0) < 0 }
            if hasNegative { result.append(.fastenerValueInvalid(group.id)) }
        }
        return result
    }

    /// 入力から整備記録を作ります。
    ///
    /// 責務: 検証済みの入力を保存用の記録へ変換します。軽整備には締結グループを持たせません。
    /// - Parameter modifiedAt: 更新日時。
    func makeRecord(modifiedAt: Date) -> MaintenanceRecord {
        MaintenanceRecord(
            id: recordID ?? MaintenanceRecordID(),
            vehicleID: vehicleID,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            performedAt: performedAt,
            odometerKilometers: odometerKilometers,
            notes: notes,
            workItems: workItems,
            photos: photos,
            fastenerGroups: kind == .heavy ? fastenerGroups : [],
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}
