#if os(iOS)
/// iOS HOMEのアダプター導線から通知する表示操作です。
enum IOSHomeAction: Equatable {
    /// デフォルトアダプターの設定開始を通知します。
    case adapterSetupRequested
}
#endif
