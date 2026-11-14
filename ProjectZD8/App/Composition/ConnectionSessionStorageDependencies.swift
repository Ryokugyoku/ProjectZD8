import Foundation
import GRDB

/// 同じ製品DB Queueを共有する接続session側と取得証拠側の保存先を束ねます。
struct ConnectionSessionStorageDependencies {
    /// 接続session、Rawログ、消去を扱う保存先の型です。
    typealias SessionStorage = any ConnectionSessionRepository
        & ConnectionSessionRawLogRepository
        & ConnectionSessionErasureRepository
        & AccountConnectionSessionErasureRepository
    /// 取得manifest、batch、取得終了を扱う保存先の型です。
    typealias AcquisitionStorage = any ConnectionSessionAcquisitionRepository
        & ConnectionSessionAcquisitionBatchRepository
        & ConnectionSessionAcquisitionTerminationRepository

    /// 接続session、Rawログ、消去の保存先です。
    let sessions: SessionStorage
    /// 取得証拠の保存先です。`sessions` と同じDB Queueを共有します。
    let acquisition: AcquisitionStorage
    /// Rawと取得証跡をチャンク単位で保存する保存先です。`sessions` と同じDB Queueを共有します。
    let chunks: any ConnectionSessionAcquisitionChunkRepository
    /// 連続取得区間の保存先です。`sessions` と同じDB Queueを共有します。
    let segments: any ConnectionSessionSegmentRepository
    /// 連続取得区間の間の欠損の保存先です。`sessions` と同じDB Queueを共有します。
    let gaps: any ConnectionSessionGapRepository

    /// 共有製品DB Queueをsession側と取得証拠側へ注入します。
    ///
    /// 責務: 製品DB Queueを全Repositoryへ注入し、準備失敗時はすべてを明示的利用不能境界へ揃えます。
    /// - Parameters:
    ///   - openDatabaseQueue: 共有製品DB Queueを返す処理。製品では `ApplicationDatabaseConnection.databaseQueue` を渡します。
    ///   - performanceEvents: 取得証拠writeを通知する匿名計測境界。
    /// - Returns: 同じQueueを共有する保存先、またはすべて利用不能な保存先。
    static func makeProduction(
        openDatabaseQueue: () throws -> DatabaseQueue,
        performanceEvents: any AcquisitionPerformanceEventPort = NoOpAcquisitionPerformanceEventPort()
    ) -> ConnectionSessionStorageDependencies {
        do {
            let queue = try openDatabaseQueue()
            let sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
            let acquisition = try GRDBConnectionSessionAcquisitionRepository(
                databaseQueue: queue,
                performanceEvents: performanceEvents
            )
            return ConnectionSessionStorageDependencies(
                sessions: sessions,
                acquisition: acquisition,
                chunks: try GRDBConnectionSessionAcquisitionChunkRepository(databaseQueue: queue),
                segments: try GRDBConnectionSessionSegmentRepository(databaseQueue: queue),
                gaps: try GRDBConnectionSessionGapRepository(databaseQueue: queue)
            )
        } catch {
            let unavailable = UnavailableConnectionSessionRepository()
            return ConnectionSessionStorageDependencies(
                sessions: unavailable,
                acquisition: unavailable,
                chunks: UnavailableConnectionSessionAcquisitionChunkRepository(),
                segments: UnavailableConnectionSessionSegmentationRepository(),
                gaps: UnavailableConnectionSessionSegmentationRepository()
            )
        }
    }
}
