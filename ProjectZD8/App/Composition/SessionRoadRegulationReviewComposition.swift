import Foundation

/// 解析画面の交通規制の照合のモデルを、iOS と macOS で共有して組み立てます。
///
/// 判定は `RoadRegulationAssembly.makeEvaluation` のユースケース、利用日は版の一覧のユースケースに任せ、
/// それらを `RoadRegulationSessionReviewAdapter` で Analysis のポートへ写してモデルへ渡します。
@MainActor
enum SessionRoadRegulationReviewComposition {
    /// 解析画面の交通規制の照合のモデルを生成します。
    ///
    /// 責務: 位置の保存先・判定のユースケース・版の一覧のユースケースを作り、closure としてアダプターへ結び付け、
    /// 配布ページの URL と共にモデルへ注入します。
    /// - Parameters:
    ///   - database: プロセス内で共有する製品DB接続。
    ///   - rawLogs: 接続セッションの Raw ログの保存先(車速を読む)。
    ///   - repositoryFactory: 保存先の準備と、失敗時の診断・差し替えを行う部品。`nil` なら統合ログへ診断を残す既定の部品。
    /// - Returns: `idle` から始まる照合のモデル。アカウントは `accountIdentifierChanged`、段階は `readinessChanged` で受け取ります。
    static func makeModel(
        database: ApplicationDatabaseConnection,
        rawLogs: any ConnectionSessionRawLogRepository,
        repositoryFactory: ProductDatabaseRepositoryFactory? = nil
    ) -> SessionRoadRegulationReviewModel {
        let factory = repositoryFactory ?? .init()
        let locations = factory.makeConnectionSessionLocationRepository(database: database)
        let evaluation = RoadRegulationAssembly.makeEvaluation(
            database: database,
            locations: locations,
            rawLogs: rawLogs,
            repositoryFactory: factory
        )
        let list = ListRoadRegulationDatasetsUseCase(datasets: factory.makeRoadRegulationDatasetRepository(database: database))
        let reviewPort = RoadRegulationSessionReviewAdapter(
            evaluate: { sessionID in try await evaluation.execute(sessionID: sessionID) },
            listDatasets: { try list.execute() },
            sourceURL: sourceURL()
        )
        return SessionRoadRegulationReviewModel(reviewPort: reviewPort)
    }

    /// 交通規制データの配布ページの URL を返します。
    ///
    /// 責務: 出典の表示と同じ `RoadRegulationAttribution.sourceURLString` を URL にします(定数のため解釈は失敗しない)。
    /// - Returns: 配布ページの URL。
    private static func sourceURL() -> URL {
        guard let url = URL(string: RoadRegulationAttribution.sourceURLString) else {
            preconditionFailure("RoadRegulationAttribution.sourceURLString must be a valid URL")
        }
        return url
    }
}
