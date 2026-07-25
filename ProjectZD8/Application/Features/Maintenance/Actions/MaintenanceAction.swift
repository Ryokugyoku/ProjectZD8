import Foundation

/// 整備画面とAppからMaintenanceへ通知する型付き操作です。
enum MaintenanceAction {
    /// 認証済みアカウントへ整備スコープを切り替えます。
    case accountIdentifierChanged(String?)
    /// 現在の登録車両集合を整備対象選択へ反映します。
    case vehiclesChanged([VehicleProfile])
    /// 一覧表示する車両を選択します。
    case vehicleSelected(VehicleID)
    /// 一覧の整備区分フィルターを変更します。
    case kindFilterChanged(MaintenanceKind?)
    /// 選択車両の新規整備入力を開始します。
    case createRequested(MaintenanceKind)
    /// 保存済み整備記録の編集を開始します。
    case editRequested(MaintenanceRecordID)
    /// 画面で変更した未保存入力を反映します。
    case draftChanged(MaintenanceEditorDraft)
    /// 現在の入力へ作業項目を追加します。
    case workItemAdded
    /// 現在の入力から作業項目を削除します。
    case workItemRemoved(UUID)
    /// 重整備入力へ締結グループを追加します。
    case fastenerGroupAdded
    /// 締結グループへ個別の締結位置を追加します。
    case fastenerAdded(UUID)
    /// 個別締結を現在日時で完了証跡として確定します。
    case fastenerConfirmed(UUID, UUID)
    /// 最新の作業写真を個別締結証跡へ関連付けます。
    case latestPhotoLinked(UUID, UUID)
    /// 現在の入力から締結グループを削除します。
    case fastenerGroupRemoved(UUID)
    /// ファイル選択済み写真を現在の入力へ追加します。
    case photoSelected(URL)
    /// 現在の入力から写真を削除します。
    case photoRemoved(UUID)
    /// 現在の入力を保存します。
    case saveRequested
    /// 保存せず一覧へ戻ります。
    case editingCancelled
    /// 指定記録を全端末から削除する墓石へ更新します。
    case deleteRequested(MaintenanceRecordID)
    /// ローカルとCloudKitの再同期を要求します。
    case refreshRequested
}
