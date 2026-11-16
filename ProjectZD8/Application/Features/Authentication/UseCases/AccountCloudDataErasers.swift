/// アカウント削除でCloudKit上のデータを消す3つの境界をまとめた値です。
@MainActor
struct AccountCloudDataErasers {
    /// CloudKit上のセッション概要、Raw Asset、Mac受領証、および削除マーカーを削除する境界です。
    let sessionTransfers: any ConnectionSessionTransferRepository

    /// CloudKitと端末キャッシュの車両カタログを削除する境界です。
    let vehicleDataEraser: any AccountVehicleDataErasurePort

    /// CloudKit上の整備カタログ(整備記録と整備写真)を削除する境界です。
    let maintenanceDataEraser: any AccountMaintenanceDataErasurePort

    /// クラウド削除の3境界を束ねます。
    ///
    /// 責務: `DeleteAccountUseCase` が受け取るクラウド削除の依存を1つの値にまとめ、引数の数を抑えます。
    /// - Parameters:
    ///   - sessionTransfers: CloudKit上の運転データ削除境界。
    ///   - vehicleDataEraser: CloudKitと端末キャッシュの車両カタログ削除境界。
    ///   - maintenanceDataEraser: CloudKit上の整備カタログ削除境界。
    init(
        sessionTransfers: any ConnectionSessionTransferRepository,
        vehicleDataEraser: any AccountVehicleDataErasurePort,
        maintenanceDataEraser: any AccountMaintenanceDataErasurePort
    ) {
        self.sessionTransfers = sessionTransfers
        self.vehicleDataEraser = vehicleDataEraser
        self.maintenanceDataEraser = maintenanceDataEraser
    }
}
