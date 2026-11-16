/// HOMEの「アダプターを設定」由来の注目要求を、設定画面がいま強調表示すべきかを判定します。SwiftUIに依存しない純粋型です。
///
/// 強調(スクロールと振動)はボタンを押すたびに遷移直後の1回だけで、通常の手動遷移では出しません。iOSとmacOSで共有します。
nonisolated struct AdapterSettingsAttentionPolicy: Sendable {
    /// 判定を生成します。
    ///
    /// 責務: 状態を持たない判定を作ります。
    init() {}

    /// 注目要求を強調表示すべきかどうかを返します。
    ///
    /// 責務: 未消費の要求が残っていて、その番号をこの画面がまだ処理していない時だけ `true` を返します。
    /// - Parameters:
    ///   - sequence: 処理対象の注目要求番号。
    ///   - isPending: 未消費の要求が残っているかどうか。
    ///   - handledSequence: この画面が最後に処理した要求番号。
    /// - Returns: 強調表示して要求を消費すべきなら `true`。
    func shouldPresent(sequence: UInt, isPending: Bool, handledSequence: UInt) -> Bool {
        isPending && sequence != handledSequence
    }
}
