/// 車両不明ログのテストで、保存先の失敗として投げるエラーです。
enum VehicleUnknownSessionTestError: Error, Equatable {
    /// 保存先を使えなかったことを表します。
    case storageFailed
}
