import GRDB

/// プロセス内で1回だけ開いた製品DB接続、または開けなかった失敗を保持します。
///
/// `ProjectZD8App.init` で1件だけ生成し、製品DBを使う全Repositoryの組み立てへ明示的に渡します。
struct ApplicationDatabaseConnection {
    /// 生成時に1回だけ開いた製品DB Queue、または開けなかった原因です。
    private let openResult: Result<DatabaseQueue, any Error>

    /// 製品DBを1回だけ開き、その結果を保持します。
    ///
    /// 責務: 注入された処理を1回だけ実行し、成功したQueueまたは失敗原因を保持します。
    /// - Parameter openDatabaseQueue: 製品DB Queueを開く処理。既定はApplication Support内の製品DB。
    init(
        openDatabaseQueue: () throws -> DatabaseQueue = ProjectZD8DatabaseLocation.openApplicationDatabaseQueue
    ) {
        openResult = Result(catching: openDatabaseQueue)
    }

    /// 共有している製品DB Queueを返します。
    ///
    /// 責務: 生成時に開いた同一のQueueを返し、開けなかった場合は保持している失敗を再送出します。
    /// - Returns: プロセス内で共有する製品DB Queue。Migrationは受け取ったRepositoryが適用します。
    /// - Throws: 生成時に製品DBを開けなかった原因のエラー。
    func databaseQueue() throws -> DatabaseQueue {
        try openResult.get()
    }
}
