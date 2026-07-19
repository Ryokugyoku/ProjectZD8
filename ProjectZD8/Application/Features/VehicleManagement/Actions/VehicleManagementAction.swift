import Foundation

/// 車両一覧、登録確認、編集からApplicationへ通知する操作です。
enum VehicleManagementAction {
    /// 認証済みアカウントへ車両スコープを切り替えます。
    case accountIdentifierChanged(String?)
    /// HOME接続操作からOBD識別を要求します。
    case identifyRequested(OBDConnectionEndpoint)
    /// 直前と同じOBD終端で識別を再試行します。
    case identificationRetryRequested
    /// 未登録の車両識別結果を受け入れて編集へ進みます。
    case identificationConfirmed
    /// 未登録の車両識別子に対する登録導線をキャンセルします。
    case registrationCancelled
    /// 新規または既存プロフィールを保存します。
    case vehicleSaved(VehicleProfile)
    /// 指定車両の編集を開始します。
    case editRequested(VehicleID)
    /// プロフィール編集を終了します。
    case editCancelled
    /// 編集中プロフィールへユーザーが選んだ写真を読み込みます。
    case photoSelected(URL)
    /// 指定車両を削除します。
    case vehicleDeleted(VehicleID)
    /// 同期先から車両一覧を再読込します。
    case refreshRequested
}
