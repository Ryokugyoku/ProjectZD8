import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 接続session側と取得証拠側が同じ製品DB Queueを共有する組立と、準備失敗時の利用不能境界を検証します。
final class ConnectionSessionStorageDependenciesTests: XCTestCase {
    /// DB Queueを開けない場合に投げるテスト用エラーです。
    private struct OpenFailure: Error {}

    /// Queue作成成功時にGRDB実装が両側へ組み立てられます。
    ///
    /// 責務: `sessions` と `acquisition` が利用不能境界ではなくGRDB Repositoryであることを確認します。
    func testMakeProductionReturnsGRDBRepositoriesWhenQueueOpens() throws {
        let queue = try DatabaseQueue()

        let dependencies = ConnectionSessionStorageDependencies.makeProduction(openDatabaseQueue: { queue })

        XCTAssertTrue(dependencies.sessions is GRDBConnectionSessionRepository)
        XCTAssertTrue(dependencies.acquisition is GRDBConnectionSessionAcquisitionRepository)
    }

    /// 両Repositoryが渡されたQueueそのものを使います。
    ///
    /// 責務: sessionsとacquisitionで保存した内容を、同じQueue上の新規Repositoryから読めることを確認します。
    func testMakeProductionSharesInjectedQueueBetweenSessionsAndAcquisition() throws {
        let queue = try DatabaseQueue()
        let dependencies = ConnectionSessionStorageDependencies.makeProduction(openDatabaseQueue: { queue })
        let session = ConnectionSession(accountIdentifier: "shared-queue", startedAt: Date(timeIntervalSince1970: 10))
        let startedAt = Date(timeIntervalSince1970: 20)

        try dependencies.sessions.save(session)
        try dependencies.acquisition.saveStartOnce(manifest: try makeManifest(), startedAt: startedAt, for: session.id)

        let freshSessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let freshAcquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        XCTAssertEqual(try freshSessions.sessions(for: "shared-queue"), [session])
        XCTAssertEqual(try freshAcquisition.manifest(for: session.id).manifestVersion, 1)
        let boundaries = try freshAcquisition.boundaryEvidence(for: session.id)
        XCTAssertEqual(boundaries.count, 1)
        guard case let .started(at) = try XCTUnwrap(boundaries.first) else {
            return XCTFail("開始境界ではありません")
        }
        XCTAssertEqual(at.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    /// 取得証拠writeが渡されたperformance境界へ通知されます。
    ///
    /// 責務: 既定のNoOpではなく引数のportが、manifest保存のbegin・queue通過・成功endを受けることを確認します。
    func testMakeProductionReportsAcquisitionWritesToInjectedPerformancePort() throws {
        let queue = try DatabaseQueue()
        let spy = StorageDependenciesPerformanceEventSpy()
        let dependencies = ConnectionSessionStorageDependencies.makeProduction(
            openDatabaseQueue: { queue },
            performanceEvents: spy
        )
        let session = ConnectionSession(accountIdentifier: "perf", startedAt: Date(timeIntervalSince1970: 10))
        try dependencies.sessions.save(session)
        XCTAssertTrue(spy.snapshot().isEmpty)

        try dependencies.acquisition.saveStartOnce(
            manifest: try makeManifest(),
            startedAt: Date(timeIntervalSince1970: 20),
            for: session.id
        )

        XCTAssertEqual(
            spy.snapshot(),
            ["begin:manifestPersistence", "queue:manifestPersistence", "end:manifestPersistence:succeeded"]
        )
    }

    /// Queueを開けない場合は両方が利用不能境界になります。
    ///
    /// 責務: opener失敗を成功扱いにせず、両方を利用不能境界へ揃えることを確認します。
    func testMakeProductionUsesUnavailableRepositoriesWhenOpenerThrows() {
        let dependencies = ConnectionSessionStorageDependencies.makeProduction(openDatabaseQueue: { throw OpenFailure() })

        XCTAssertTrue(dependencies.sessions is UnavailableConnectionSessionRepository)
        XCTAssertTrue(dependencies.acquisition is UnavailableConnectionSessionRepository)
    }

    /// Migrationに失敗する読取専用Queueでも両方が利用不能境界になります。
    ///
    /// 責務: Queueは開けるがschemaを作れない場合に、利用不能境界へ揃えることを確認します。
    func testMakeProductionUsesUnavailableRepositoriesWhenMigrationFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ConnectionSessionStorageDependenciesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "empty.sqlite").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: nil))
        var configuration = Configuration()
        configuration.readonly = true
        let readonlyQueue = try DatabaseQueue(path: path, configuration: configuration)
        XCTAssertThrowsError(try GRDBConnectionSessionRepository(databaseQueue: readonlyQueue))

        let dependencies = ConnectionSessionStorageDependencies.makeProduction(openDatabaseQueue: { readonlyQueue })

        XCTAssertTrue(dependencies.sessions is UnavailableConnectionSessionRepository)
        XCTAssertTrue(dependencies.acquisition is UnavailableConnectionSessionRepository)
    }

    /// 最小のcanonical取得manifestを作ります。
    ///
    /// 責務: 保存・往復に使う単一PIDのmanifestを生成します。
    private func makeManifest() throws -> ConnectionSessionAcquisitionManifest {
        let request = OBDPIDRequest(service: 1, pid: 12)
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "deps", buildVersion: "local"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
            pidDefinitions: [
                AcquisitionPIDDefinitionSnapshot(
                    request: request,
                    capabilitySupport: .supported,
                    isCollectionEnabled: true,
                    definitionRevision: 1,
                    requiredByteCount: 1,
                    definitionIdentity: AcquisitionPIDDefinitionIdentity(canonicalizationVersion: 1, expression: "A"),
                    unit: "unit",
                    validityRange: try .inclusive(minimum: 0, maximum: 255)
                )
            ],
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }
}

/// 受け取ったperformance eventを文字列列としてthread-safeに記録するspyです。
private final class StorageDependenciesPerformanceEventSpy: @unchecked Sendable, AcquisitionPerformanceEventPort {
    /// event列と採番への並行アクセスを直列化します。
    private let lock = NSLock()
    /// 次に割り当てる匿名interval番号です。
    private var nextIdentifier: UInt64 = 1
    /// 観測済みevent列です。
    private var events: [String] = []

    /// 空のevent記録先を生成します。
    ///
    /// 責務: テスト用event列を初期化します。
    init() {}

    /// 区間開始を記録してtokenを返します。
    ///
    /// 責務: 開始通知を操作名付きeventへ変換し一意なtokenを返します。
    /// - Parameters:
    ///   - operation: 計測する操作。
    ///   - context: 匿名取得位置。
    /// - Returns: 後続通知に再利用するtoken。
    func begin(
        _ operation: AcquisitionPerformanceOperation,
        context: AcquisitionPerformanceContext
    ) -> AcquisitionPerformanceInterval {
        lock.lock()
        defer { lock.unlock() }
        let interval = AcquisitionPerformanceInterval(identifier: nextIdentifier, operation: operation, context: context)
        nextIdentifier += 1
        events.append("begin:\(operation)")
        return interval
    }

    /// DB Queue通過を記録します。
    ///
    /// 責務: Queue通過通知を操作名付きeventへ変換します。
    /// - Parameter interval: 開始済み区間。
    func queueDidEnter(_ interval: AcquisitionPerformanceInterval) {
        lock.lock()
        defer { lock.unlock() }
        events.append("queue:\(interval.operation)")
    }

    /// 区間終了を記録します。
    ///
    /// 責務: 終了通知を操作名と結果付きeventへ変換します。
    /// - Parameters:
    ///   - interval: 開始済み区間。
    ///   - outcome: 完了結果。
    func end(_ interval: AcquisitionPerformanceInterval, outcome: AcquisitionPerformanceOutcome) {
        lock.lock()
        defer { lock.unlock() }
        events.append("end:\(interval.operation):\(outcome.rawValue)")
    }

    /// 現在のevent列を返します。
    ///
    /// 責務: 内部列を検証用snapshotへ変換します。
    /// - Returns: 呼出し時点のevent列。
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
