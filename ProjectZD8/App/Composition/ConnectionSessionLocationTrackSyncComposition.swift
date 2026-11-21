/// 走行ルート(位置の軌跡)の iCloud 同期と削除に使う依存関係を、iOS と macOS で共有して組み立てます。
///
/// 削除の経路(セッションの全端末削除・車両削除・アカウント削除)には軌跡の削除を足した転送 Repository を、
/// アップロード(iPhone だけ)と取得(段階3)には GRDB の同期記録と CloudKit の軌跡 Repository を結び付けます。
@MainActor
enum ConnectionSessionLocationTrackSyncComposition {
    /// 既存の転送 Repository の削除に、軌跡のレコードの削除を足した転送 Repository を生成します。
    ///
    /// 責務: CloudKit の既存の転送 Repository を、軌跡の CloudKit Repository で削除を補うデコレーターで包みます。
    /// - Returns: `deleteSession` と `deleteAll` が「既存の削除 → 軌跡の削除」の順に実行される転送 Repository。
    static func makeErasingTransferRepository() -> any ConnectionSessionTransferRepository {
        LocationTrackErasingConnectionSessionTransferRepository(
            base: CloudKitConnectionSessionTransferRepository(),
            locationTracks: CloudKitConnectionSessionLocationTrackRepository()
        )
    }

    /// 軌跡のアップロードのユースケースを生成します。iPhone の配線だけで使います。
    ///
    /// 責務: 同期記録の保存先・軌跡の CloudKit Repository・全端末の削除の印・アカウント削除の確認を結び付けます。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 削除済みの掃除と、送信が必要な軌跡のアップロードを行うユースケース。
    static func makeUploadUseCase(database: ApplicationDatabaseConnection) -> UploadConnectionSessionLocationTracksUseCase {
        let transferRepository = CloudKitConnectionSessionTransferRepository()
        return UploadConnectionSessionLocationTracksUseCase(
            syncRepository: makeSyncRepository(database: database),
            cloudRepository: CloudKitConnectionSessionLocationTrackRepository(),
            deletedSessionIDs: { accountIdentifier in
                try await transferRepository.deletedSessionIDs(for: accountIdentifier)
            },
            accountDeletionCheck: AccountDeletionMarkerComposition.check
        )
    }

    /// 軌跡の取得と復元のユースケースを生成します。段階3の画面が使います。
    ///
    /// 責務: 同期記録の保存先と軌跡の CloudKit Repository を取得のユースケースへ結び付けます。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: ローカルの軌跡を返すか、iCloud から取得して復元するユースケース。
    static func makeLoadUseCase(database: ApplicationDatabaseConnection) -> LoadConnectionSessionLocationTrackUseCase {
        LoadConnectionSessionLocationTrackUseCase(
            syncRepository: makeSyncRepository(database: database),
            cloudRepository: CloudKitConnectionSessionLocationTrackRepository()
        )
    }

    /// 軌跡の同期記録の保存先を生成します。
    ///
    /// 責務: 製品DBの準備に応じて GRDB の保存先か、明示的に失敗する代替を返します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: 軌跡と同期記録の読み書き先。
    private static func makeSyncRepository(
        database: ApplicationDatabaseConnection
    ) -> any ConnectionSessionLocationTrackSyncRepository {
        ProductDatabaseRepositoryFactory().makeConnectionSessionLocationTrackSyncRepository(database: database)
    }
}
