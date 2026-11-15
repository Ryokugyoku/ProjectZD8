/// 常駐リンク上のアダプターを初期化し、チップ種別とATMA対応可否を判定する能力です。
@MainActor
protocol AdapterLinkInitializationPort: AnyObject {
    /// アダプターを初期化して判定結果を返します。
    ///
    /// 責務: `ready` のリンク上でアダプターを初期化し、チップ種別とATMAの試行結果を1件の証拠値にまとめます。
    /// 取得モードは切り替えません(PIDポーリング固定)。
    /// - Returns: チップ種別とATMA判定結果。
    /// - Throws: 送受信の失敗・応答不正・キャンセルなど、初期化を完了できなかった場合のエラー。
    func initializeAdapter() async throws -> AcquisitionAdapterProbeEvidence
}
