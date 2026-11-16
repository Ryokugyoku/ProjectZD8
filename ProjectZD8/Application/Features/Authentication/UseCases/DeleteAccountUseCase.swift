/// アカウント保存データとログイン識別子を順序付けて削除します。
@MainActor
struct DeleteAccountUseCase {
    /// 他端末へ新しいセッション失効世代を発行する境界です。
    private let sessionRevocation: any AccountSessionRevocationPort

    /// CloudKit上のセッション概要、Raw Asset、Mac受領証、および削除マーカーを削除する境界です。
    private let sessionTransfers: any ConnectionSessionTransferRepository

    /// CloudKitと端末キャッシュの車両カタログを削除する境界です。
    private let vehicleDataEraser: any AccountVehicleDataErasurePort

    /// CloudKit上の整備カタログ(整備記録と整備写真)を削除する境界です。
    private let maintenanceDataEraser: any AccountMaintenanceDataErasurePort

    /// クラウド削除の完了を、他端末向けの削除済みの印として残す境界です。未設定なら印を残しません。
    private let deletionMarker: (any AccountDeletionMarkerPort)?

    /// アカウントに属する同期設定と端末設定を消去する境界です。
    private let dataEraser: any AccountDataErasurePort

    /// 最後に削除する保存済みログイン識別子の境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// 失効同期、データ消去、認証セッション保存の各境界を注入します。
    ///
    /// 責務: アカウント削除順序をCloudKit消去(運転データ、車両、整備)、削除済みの印の保存、失効発行、ローカル消去、資格情報削除へ固定します。
    /// - Parameters:
    ///   - sessionRevocation: 他端末へセッション失効を発行する境界。
    ///   - sessionTransfers: CloudKit上の運転データ削除境界。
    ///   - vehicleDataEraser: CloudKitと端末キャッシュの車両カタログ削除境界。
    ///   - maintenanceDataEraser: CloudKit上の整備カタログ削除境界。
    ///   - dataEraser: アカウントに属するアプリ保存データの消去境界。
    ///   - sessionStore: 保存済みAppleユーザー識別子の削除境界。
    ///   - deletionMarker: クラウド削除の完了後に削除済みの印を保存する境界。省略時は印を残しません。
    init(
        sessionRevocation: any AccountSessionRevocationPort,
        sessionTransfers: any ConnectionSessionTransferRepository,
        vehicleDataEraser: any AccountVehicleDataErasurePort,
        maintenanceDataEraser: any AccountMaintenanceDataErasurePort,
        dataEraser: any AccountDataErasurePort,
        sessionStore: any AuthenticationSessionStorePort,
        deletionMarker: (any AccountDeletionMarkerPort)? = nil
    ) {
        self.deletionMarker = deletionMarker
        self.sessionRevocation = sessionRevocation
        self.sessionTransfers = sessionTransfers
        self.vehicleDataEraser = vehicleDataEraser
        self.maintenanceDataEraser = maintenanceDataEraser
        self.dataEraser = dataEraser
        self.sessionStore = sessionStore
    }

    /// 指定アカウントのCloudKit全データを削除し、成功後に他端末へ失効通知してからローカルデータとログイン識別子を削除します。
    ///
    /// 責務: 1件の認証済みアカウントを再試行可能な順序(クラウド削除、失効発行、ローカル消去、資格情報削除)で端末から削除します。
    /// クラウド削除と削除済みの印の保存が1つでも失敗したら失効通知もローカル消去もしません。車両のクラウド削除が成功した直後に車両の端末キャッシュも消します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: CloudKit、ローカル保存、またはログイン識別子の削除を完了できない場合のエラー。
    func execute(userIdentifier: String) async throws {
        guard !userIdentifier.isEmpty else {
            throw AuthenticationSessionStoreError.unavailable
        }
        let vehicleIDs = vehicleDataEraser.localVehicleIDs(for: userIdentifier)
        try await sessionTransfers.deleteAll(for: userIdentifier)
        try await vehicleDataEraser.deleteAllVehicleData(for: userIdentifier)
        vehicleDataEraser.removeLocalVehicleCache(for: userIdentifier)
        try await maintenanceDataEraser.deleteAllMaintenanceData(for: userIdentifier)
        try await deletionMarker?.markDeleted(userIdentifier)
        sessionRevocation.publishRevocation(for: userIdentifier)
        try await dataEraser.eraseAllData(for: userIdentifier, knownVehicleIDs: vehicleIDs)
        try sessionStore.removeUserIdentifier()
    }
}
