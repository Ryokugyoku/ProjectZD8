/// 解析画面の走行ルート(色分けとグラフ連動)のモデルを、iOS と macOS で共有して組み立てます。
///
/// 軌跡の取得と復元は段階2の `ConnectionSessionLocationTrackSyncComposition.makeLoadUseCase(database:)` に任せ、
/// LogHistory の判定を Analysis のポートへ写す `RouteAnalysisTrackAdapter` を通してモデルへ渡します。
@MainActor
enum RouteAnalysisComposition {
    /// 解析画面の走行ルートのモデルを生成します。
    ///
    /// 責務: 軌跡の取得のユースケースを読み込みの closure としてアダプターへ結び付け、そのアダプターをモデルへ注入します。
    /// - Parameter database: プロセス内で共有する製品DB接続。
    /// - Returns: `idle` から始まる解析の走行ルートのモデル。アカウントは `accountIdentifierChanged` で受け取ります。
    static func makeModel(database: ApplicationDatabaseConnection) -> RouteAnalysisModel {
        let loadTrack = ConnectionSessionLocationTrackSyncComposition.makeLoadUseCase(database: database)
        let trackPort = RouteAnalysisTrackAdapter(
            load: { sessionID, accountIdentifier in
                try await loadTrack.execute(sessionID: sessionID, accountIdentifier: accountIdentifier)
            }
        )
        return RouteAnalysisModel(trackPort: trackPort)
    }
}
