/// 1件の接続セッションをCloudKitと現在端末から削除します。
@MainActor
struct DeleteConnectionSessionEverywhereUseCase {
    /// 現在端末のセッション物理削除境界です。
    private let localRepository: any ConnectionSessionErasureRepository
    /// 全端末へ削除を伝播するCloudKit境界です。
    private let transferRepository: any ConnectionSessionTransferRepository

    /// ローカル保存先と端末間転送先を固定して生成します。
    ///
    /// 責務: 1件の全端末削除処理をローカル保存先とCloudKit削除境界へ結び付けます。
    /// - Parameters:
    ///   - localRepository: 現在端末のセッション物理削除境界。
    ///   - transferRepository: 削除マーカーと転送データを管理するCloudKit境界。
    init(
        localRepository: any ConnectionSessionErasureRepository,
        transferRepository: any ConnectionSessionTransferRepository
    ) {
        self.localRepository = localRepository
        self.transferRepository = transferRepository
    }

    /// 削除マーカーを公開してCloud上のPayloadを除去した後、現在端末から物理削除します。
    ///
    /// 責務: 1件の終了済みセッションを全端末削除対象として確定し現在端末から物理削除します。
    /// - Parameter session: 削除する終了済み接続セッション。
    /// - Throws: 取得中セッション、CloudKit削除、またはローカル物理削除に失敗した場合のエラー。
    func execute(session: ConnectionSession) async throws {
        guard session.endedAt != nil else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        try await transferRepository.deleteSession(
            session.id,
            for: session.accountIdentifier
        )
        try localRepository.deleteSession(
            session.id,
            for: session.accountIdentifier
        )
    }
}
