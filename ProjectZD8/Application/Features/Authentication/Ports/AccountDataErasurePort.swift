/// 認証済みアカウントに属するアプリ保存データの消去を抽象化します。
@MainActor
protocol AccountDataErasurePort: AnyObject {
    /// 指定アカウントの運転データ、整備記録、同期設定、端末設定を消去します。
    ///
    /// 責務: 1件のAppleユーザー識別子に対応するアプリ保存データを削除済み状態へします。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: ローカル運転データまたは整備記録を完全に削除できない場合の保存先エラー。
    func eraseAllData(for userIdentifier: String) async throws

    /// 事前に控えた登録車両IDを使って、指定アカウントのアプリ保存データを消去します。
    ///
    /// 責務: 車両キャッシュを先に消した後でも、車両別PID設定を取りこぼさず消去します。
    /// 既定実装は控えたIDを使わず `eraseAllData(for:)` へ委ねます。
    /// - Parameters:
    ///   - userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    ///   - vehicleIDs: 車両キャッシュ削除より前に控えた登録車両ID群。
    /// - Throws: ローカルデータを完全に削除できない場合の保存先エラー。
    func eraseAllData(for userIdentifier: String, knownVehicleIDs vehicleIDs: [VehicleID]) async throws
}

extension AccountDataErasurePort {
    /// 控えた車両IDを使わず、通常の消去へ委ねます。
    ///
    /// 責務: 車両IDを個別に扱わない実装を `eraseAllData(for:)` へ結び付けます。
    /// - Parameters:
    ///   - userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    ///   - vehicleIDs: 使用しない車両ID群。
    /// - Throws: `eraseAllData(for:)` が投げるエラー。
    func eraseAllData(for userIdentifier: String, knownVehicleIDs vehicleIDs: [VehicleID]) async throws {
        try await eraseAllData(for: userIdentifier)
    }
}
