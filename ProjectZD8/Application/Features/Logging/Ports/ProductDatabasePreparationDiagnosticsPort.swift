/// 製品DBの準備(DBを開く・Migration・初期データ登録)に失敗して保存先を利用不能へ差し替えたことを、診断記録へ残す境界です。
///
/// 差し替えのふるまい(`Unavailable*` を返す)は変えず、捨てていた元のエラーだけをこの境界へ渡します。
/// 製品DBの主な利用者は記録ログ(接続セッション)のため、Logging が所有します。
@MainActor
protocol ProductDatabasePreparationDiagnosticsPort: AnyObject {
    /// 保存先の準備に失敗し、利用不能へ差し替えたことを記録します。
    ///
    /// 責務: 1件の保存先の種類と元のエラーを診断記録へ渡します。
    /// - Parameters:
    ///   - storage: 利用不能へ差し替えた保存先。
    ///   - error: 準備に失敗した元のエラー。
    func preparationFailed(_ storage: ProductDatabaseStorageKind, error: any Error)
}
