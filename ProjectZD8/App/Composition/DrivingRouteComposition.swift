/// セッション詳細の走行ルート(地図)のモデルを、iOS と macOS で共有して組み立てます。
///
/// 軌跡の取得と復元は段階2の `ConnectionSessionLocationTrackSyncComposition.makeLoadUseCase(database:)` に任せ、
/// 判定・形・要約・失敗の分類はモデルの既定の純粋型を使います。
@MainActor
enum DrivingRouteComposition {
    /// セッション詳細の走行ルートのモデルを生成します。
    ///
    /// 責務: 軌跡の取得のユースケースを、セッション ID とアカウント識別子を受け取る読み込みの closure としてモデルへ結び付けます。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: `idle` から始まる走行ルートのモデル。アカウントは `accountIdentifierChanged` で受け取ります。
    static func makeDetailModel(database: ApplicationDatabaseConnection) -> DrivingRouteDetailModel {
        let loadTrack = ConnectionSessionLocationTrackSyncComposition.makeLoadUseCase(database: database)
        return DrivingRouteDetailModel(
            load: { sessionID, accountIdentifier in
                try await loadTrack.execute(sessionID: sessionID, accountIdentifier: accountIdentifier)
            }
        )
    }
}
