import Foundation

/// 交通規制データの設定画面のモデルと、走行の判定のユースケースを、iOS と macOS で共有して組み立てます。
///
/// 製品DBを開けない時は、保存先を利用不能な代替に差し替え、診断へ `.roadRegulations` を1件だけ残します
/// (`ProductDatabaseRepositoryFactory` の流儀)。取得した ZIP は `Caches/RoadRegulationDownloads/` に置きます。
@MainActor
enum RoadRegulationAssembly {
    /// 取得した ZIP を置く、Caches の下のフォルダ名です。
    static let downloadDirectoryName = "RoadRegulationDownloads"

    /// 設定画面の交通規制データのモデルを生成します。
    ///
    /// 責務: 版の保存先・取得元・アーカイブの読み取り・空き容量を1回ずつ作り、一覧・取り込み・削除・一覧の取得・掃除の
    /// ユースケースへ同じインスタンスを渡してモデルへ注入します。
    /// - Parameters:
    ///   - database: プロセス内で共有する製品DB接続。
    ///   - repositoryFactory: 保存先の準備と、失敗時の診断・差し替えを行う部品。`nil` なら統合ログへ診断を残す既定の部品。
    /// - Returns: 空の47行から始まる設定のモデル。版は `appeared` で読みます。
    static func makeSettingsModel(
        database: ApplicationDatabaseConnection,
        repositoryFactory: ProductDatabaseRepositoryFactory? = nil
    ) -> RoadRegulationSettingsModel {
        let datasets = (repositoryFactory ?? .init()).makeRoadRegulationDatasetRepository(database: database)
        let cachesDirectory = cachesDirectoryURL()
        let source = URLSessionJARTICRoadRegulationSource(
            downloadDirectory: cachesDirectory.appendingPathComponent(downloadDirectoryName, isDirectory: true)
        )
        return RoadRegulationSettingsModel(
            list: ListRoadRegulationDatasetsUseCase(datasets: datasets),
            importer: ImportRoadRegulationDatasetUseCase(
                source: source,
                archiveReader: JARTICRoadRegulationArchiveReader(),
                datasets: datasets,
                capacity: VolumeRoadRegulationStorageCapacityAdapter(volumeURL: cachesDirectory)
            ),
            remover: RemoveRoadRegulationDatasetUseCase(datasets: datasets),
            catalog: FetchRoadRegulationCatalogUseCase(source: source),
            purge: PurgeRoadRegulationLeftoversUseCase(datasets: datasets, source: source)
        )
    }

    /// 1回の走行の交通規制の判定のユースケースを生成します(5c が使います)。
    ///
    /// 責務: 規制の検索と版の保存先を1回の準備でまとめて作り、位置と Raw の保存先と共にユースケースへ注入します。
    /// 準備に失敗した時は両方を利用不能な代替にし、診断は1件だけ残します。
    /// - Parameters:
    ///   - database: プロセス内で共有する製品DB接続。
    ///   - locations: 接続セッションの位置の保存先。
    ///   - rawLogs: 接続セッションの Raw ログの保存先(車速を読む)。
    ///   - repositoryFactory: 保存先の準備と、失敗時の診断・差し替えを行う部品。`nil` なら統合ログへ診断を残す既定の部品。
    /// - Returns: 走行の判定のユースケース。
    static func makeEvaluation(
        database: ApplicationDatabaseConnection,
        locations: any ConnectionSessionLocationRepository,
        rawLogs: any ConnectionSessionRawLogRepository,
        repositoryFactory: ProductDatabaseRepositoryFactory? = nil
    ) -> EvaluateSessionRoadRegulationsUseCase {
        let repositories = (repositoryFactory ?? .init()).prepare(.roadRegulations) {
            let queue = try database.databaseQueue()
            let datasets: any RoadRegulationDatasetRepository = try GRDBRoadRegulationDatasetRepository(databaseQueue: queue)
            let regulations: any RoadRegulationQueryRepository = try GRDBRoadRegulationQueryRepository(databaseQueue: queue)
            return (datasets: datasets, regulations: regulations)
        } unavailable: {
            let datasets: any RoadRegulationDatasetRepository = UnavailableRoadRegulationDatasetRepository()
            let regulations: any RoadRegulationQueryRepository = UnavailableRoadRegulationQueryRepository()
            return (datasets: datasets, regulations: regulations)
        }
        return EvaluateSessionRoadRegulationsUseCase(
            locations: locations,
            rawLogs: rawLogs,
            regulations: repositories.regulations,
            datasets: repositories.datasets
        )
    }

    /// 利用者の Caches のフォルダを返します。
    ///
    /// 責務: ユーザー領域の Caches を解決し、解決できない時は一時フォルダで代えます。
    /// - Returns: Caches のフォルダの URL。
    private static func cachesDirectoryURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }
}
