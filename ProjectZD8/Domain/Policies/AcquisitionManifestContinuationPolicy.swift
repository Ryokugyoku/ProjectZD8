/// 保存済みmanifestを持つセッションへ、同じセッションの続きとして取得を記録してよいかを判定します。
///
/// 取得を再試行する時や、プロセス復帰後に猶予内で同じセッションを続ける時に使います。
/// アダプター判定結果(`adapterProbeEvidence`)は比較から除きます。判定結果は接続の経路で有無が変わり
/// (常駐リンクは初期化時に判定し、手動接続は判定しません)、Rawの解釈(PID定義、要求順、各契約version)には関わらないためです。
/// これを比較に含めると、常駐リンクで始めた記録を手動接続で続ける場合やその逆で、取得が保存失敗で終わります。
/// 保存済みmanifestは書き換えないので、最初に保存した判定結果がそのまま残ります。
nonisolated struct AcquisitionManifestContinuationPolicy: Sendable {
    /// 状態を持たない判定を生成します。
    ///
    /// 責務: 続行可否の判定を構築します。
    init() {}

    /// 保存済みmanifestのセッションへ、要求されたmanifestの取得を続けて記録できるかを返します。
    ///
    /// 責務: アダプター判定結果を除くすべての項目が一致する場合だけ続行可能と判定します。
    /// - Parameters:
    ///   - stored: セッションに保存済みのmanifest。
    ///   - requested: 続きの取得が確定したmanifest。
    /// - Returns: 各契約version、アプリversion、要求順、PID定義、取得platformがすべて一致すれば `true`。
    func canContinue(
        stored: ConnectionSessionAcquisitionManifest,
        requested: ConnectionSessionAcquisitionManifest
    ) -> Bool {
        stored.manifestVersion == requested.manifestVersion
            && stored.applicationVersion == requested.applicationVersion
            && stored.schemaContractVersion == requested.schemaContractVersion
            && stored.pollingPolicyVersion == requested.pollingPolicyVersion
            && stored.orderedRequestedPIDs == requested.orderedRequestedPIDs
            && stored.pidDefinitions == requested.pidDefinitions
            && stored.acquisitionPlatform == requested.acquisitionPlatform
            && stored.modelInputManifestVersion == requested.modelInputManifestVersion
    }
}
