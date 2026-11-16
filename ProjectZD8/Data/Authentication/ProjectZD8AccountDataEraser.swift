/// ProjectZD8が現在端末に保持する運転データ、同期設定、端末固有設定を消去します。
@MainActor
final class ProjectZD8AccountDataEraser: AccountDataErasurePort {
    /// iCloud共有設定と同じ設定の端末内コピーを保持する保存先です。
    private let accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore

    /// 端末固有のデフォルトアダプター選択を保持する保存先です。
    private let defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore

    /// 接続履歴と未デコードRawログを保持するローカル保存先です。
    private let connectionSessionStorage: any AccountConnectionSessionErasureRepository

    /// 車両プロフィールと写真の端末内キャッシュ削除境界です。
    private let vehicleDataEraser: any AccountVehicleDataErasurePort

    /// 登録車両別PID対応情報と収集選択のローカル削除境界です。
    private let vehiclePIDCapabilityEraser: any AccountVehiclePIDCapabilityErasureRepository

    /// 端末内の整備記録(整備写真を含む)の削除境界です。
    private let maintenanceRecordRepository: any MaintenanceRecordRepository

    /// アカウント設定と端末固有設定の具体保存先を注入します。
    ///
    /// 責務: 現在のProjectZD8が永続化するローカル運転データと2種類の設定保存先を削除境界へ固定します。
    /// - Parameters:
    ///   - accountSettingsStore: iCloud共有設定と端末内コピーの保存先。
    ///   - defaultAdapterStore: 端末固有のデフォルトアダプター設定保存先。
    ///   - connectionSessionStorage: 接続履歴と子Rawログのローカル保存先。
    ///   - vehicleDataEraser: 車両プロフィールと写真の端末内キャッシュ削除境界。
    ///   - vehiclePIDCapabilityEraser: 登録車両別PID設定のローカル削除境界。
    ///   - maintenanceRecordRepository: 端末内整備記録の削除境界。
    init(
        accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore,
        defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore,
        connectionSessionStorage: any AccountConnectionSessionErasureRepository,
        vehicleDataEraser: any AccountVehicleDataErasurePort,
        vehiclePIDCapabilityEraser: any AccountVehiclePIDCapabilityErasureRepository,
        maintenanceRecordRepository: any MaintenanceRecordRepository
    ) {
        self.accountSettingsStore = accountSettingsStore
        self.defaultAdapterStore = defaultAdapterStore
        self.connectionSessionStorage = connectionSessionStorage
        self.vehicleDataEraser = vehicleDataEraser
        self.vehiclePIDCapabilityEraser = vehiclePIDCapabilityEraser
        self.maintenanceRecordRepository = maintenanceRecordRepository
    }

    /// 指定アカウントのローカル運転データ、整備記録、共有設定、端末内アダプター設定を消去します。
    ///
    /// 責務: 1件のアカウント削除要求を、現在の車両キャッシュから控えた車両IDを使った全端末内データの消去へ変換します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: ローカル接続履歴、Rawログ、または整備記録を完全に削除できない場合の保存先エラー。
    func eraseAllData(for userIdentifier: String) async throws {
        let vehicleIDs = vehicleDataEraser.localVehicleIDs(for: userIdentifier)
        try await eraseAllData(for: userIdentifier, knownVehicleIDs: vehicleIDs)
    }

    /// 控えた車両IDを使って、指定アカウントの端末内データを消去します。
    ///
    /// 責務: 車両キャッシュが既に消えていても、渡された車両IDの別PID設定を含めてローカルデータを消去します。
    /// - Parameters:
    ///   - userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    ///   - vehicleIDs: 車両キャッシュ削除より前に控えた登録車両ID群。
    /// - Throws: ローカル接続履歴、Rawログ、または整備記録を完全に削除できない場合の保存先エラー。
    func eraseAllData(for userIdentifier: String, knownVehicleIDs vehicleIDs: [VehicleID]) async throws {
        try connectionSessionStorage.deleteSessions(for: userIdentifier)
        try vehiclePIDCapabilityEraser.deleteCapabilities(for: vehicleIDs)
        try await maintenanceRecordRepository.replaceAll([], for: userIdentifier)
        vehicleDataEraser.removeLocalVehicleCache(for: userIdentifier)
        accountSettingsStore.remove(for: userIdentifier)
        defaultAdapterStore.remove()
    }
}
