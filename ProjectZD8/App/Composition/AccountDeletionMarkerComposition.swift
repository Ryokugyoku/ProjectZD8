/// 削除済みの印の保存先と確認関門を、全同期・保存経路で共有する1組として保持します。
@MainActor
enum AccountDeletionMarkerComposition {
    /// 印の保存・確認・解除に使う共有の境界です。
    static let marker: any AccountDeletionMarkerPort = CloudKitAccountDeletionMarkerStore()

    /// 印を確認する共有の関門です。認証モデルの生成時に、検出時の端末内ログアウトを結び付けます。
    static let gate = AccountDeletionMarkerGate(marker: marker)

    /// アップロード・保存の直前に呼ぶ確認処理です。印があるか確認できない場合は投げます。
    static let check: @MainActor (String) async throws -> Void = { accountIdentifier in
        try await gate.ensureAccountNotDeleted(for: accountIdentifier)
    }
}
