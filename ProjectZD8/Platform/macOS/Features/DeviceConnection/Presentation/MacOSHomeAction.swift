#if os(macOS)
/// macOS HOMEのアダプター導線から通知する表示操作です。
enum MacOSHomeAction: Equatable {
    /// デフォルトアダプターの設定開始を通知します。
    case adapterSetupRequested
}
#endif
