import Foundation

/// 整備画面からモデルへ送る操作です。
nonisolated enum MaintenanceAction: Sendable {
    /// 読み込みを始め、以後の変更通知を購読します。
    case started
    /// 変更通知の購読を止めます。
    case stopped
    /// 再読み込みします。
    case refreshRequested
    /// 一覧に表示する車両を選びます。
    case vehicleSelected(VehicleID)
    /// 一覧の区分絞り込みを変更します。`nil` で解除します。
    case kindFilterChanged(MaintenanceKind?)
    /// 選択車両の新規整備入力を開きます。
    case createRequested(MaintenanceKind)
    /// 保存済みの整備記録を編集します。
    case editRequested(MaintenanceRecordID)
    /// 画面で変更した入力を反映します。
    case draftChanged(MaintenanceDraft)
    /// 作業項目を追加します。
    case workItemAdded
    /// 作業項目を削除します。
    case workItemRemoved(UUID)
    /// 締結グループを追加します(重整備のみ)。
    case fastenerGroupAdded
    /// 締結グループを削除します。
    case fastenerGroupRemoved(UUID)
    /// 締結グループへ個別締結を追加します。
    case fastenerAdded(groupID: UUID)
    /// 個別締結を削除します。
    case fastenerRemoved(groupID: UUID, evidenceID: UUID)
    /// 個別締結を現在日時で完了として記録します。
    case fastenerConfirmed(groupID: UUID, evidenceID: UUID)
    /// 写真を個別締結へ関連付けます。
    case fastenerPhotoLinked(groupID: UUID, evidenceID: UUID, photoID: PhotoID)
    /// 写真と個別締結の関連付けを外します。
    case fastenerPhotoUnlinked(groupID: UUID, evidenceID: UUID, photoID: PhotoID)
    /// 写真を締結グループの分解状態の写真へ関連付けます。
    case removalPhotoLinked(groupID: UUID, photoID: PhotoID)
    /// 写真と分解状態の関連付けを外します。
    case removalPhotoUnlinked(groupID: UUID, photoID: PhotoID)
    /// 選んだ画像データを写真として追加します。
    case photoPicked(Data)
    /// 写真を外します。
    case photoRemoved(PhotoID)
    /// 写真の説明を変更します。
    case photoCaptionChanged(PhotoID, String)
    /// 入力を保存します。
    case saveRequested
    /// 保存せず編集画面を閉じます。
    case editCancelled
    /// 整備記録削除の確認を求めます。
    case deleteRequested(MaintenanceRecordID)
    /// 確認済みの削除を実行します。
    case deleteConfirmed
    /// 削除をやめます。
    case deleteCancelled
    /// 表示中の失敗を閉じます。
    case failureDismissed
}
