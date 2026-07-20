#if os(iOS)
/// iOS HOMEのアダプター導線から通知する表示操作です。
enum IOSHomeAction: Equatable {
    /// デフォルトアダプターの設定開始を通知します。
    case adapterSetupRequested
    /// OBD識別を含む車両接続フローの開始を通知します。
    case vehicleConnectionRequested(OBDConnectionEndpoint)
    /// PID取得と通信セッションの安全な終了を通知します。
    case vehicleDisconnectionRequested
    /// 警告を確認してBRZ Beta周期取得へ同意します。
    case brzBetaAccepted
    /// BRZ Betaを使用せず標準取得を選択します。
    case brzBetaDeclined
}
#endif
