import Foundation

/// 車両管理画面からモデルへ送る操作です。
nonisolated enum VehicleManagementAction: Sendable {
    /// 読み込みを始め、以後の変更通知を購読します。
    case started
    /// 変更通知の購読を止めます。
    case stopped
    /// 一覧を再読み込みします。
    case refreshRequested
    /// 車両の編集画面を開きます。
    case editRequested(VehicleID)
    /// 画面で変更した入力を反映します。動力区分が変わるとエネルギー源も整います。
    case draftChanged(VehicleEditDraft)
    /// 選んだ画像データを編集中の車両の写真にします。
    case photoPicked(Data)
    /// 編集中の車両の写真を外します。
    case photoRemoved
    /// 編集中の入力を保存します。
    case saveRequested
    /// 保存せず編集画面を閉じます。
    case editCancelled
    /// 車両削除の確認を求めます。
    case deleteRequested(VehicleID)
    /// 確認済みの車両削除を実行します。
    case deleteConfirmed
    /// 車両削除をやめます。
    case deleteCancelled
    /// 車両のPID収集設定画面を開きます。
    case pidSettingsRequested(VehicleID)
    /// PID収集設定画面を閉じます。
    case pidSettingsClosed
    /// PIDの分類絞り込みを変更します。
    case pidCategoryFilterChanged(VehiclePIDCategoryFilter)
    /// PIDの有効状態絞り込みを変更します。
    case pidEnabledFilterChanged(VehiclePIDEnabledFilter)
    /// 1つのPIDの収集有効・無効を切り替えます。
    case pidCollectionToggled(OBDPIDRequest, isEnabled: Bool)
    /// 表示中の失敗を閉じます。
    case failureDismissed
}
