/// ホームのアダプターカードが提供する主操作です。
nonisolated enum HomeAdapterPrimaryAction: Equatable, Sendable {
    /// 検出済みのアダプターへ接続します。接続先が `nil` の時はボタンを無効で表示します。
    case connect(OBDConnectionEndpoint?)
    /// アダプターの設定画面へ進みます。
    case setupAdapter
}
