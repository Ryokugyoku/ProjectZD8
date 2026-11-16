import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品DBの準備に失敗した時に元のエラーを診断へ1件残して利用不能な保存先を返し、成功時は何も残さないことを検証します。
@MainActor
final class ProductDatabaseRepositoryFactoryTests: XCTestCase {
    /// 準備に失敗させるテスト用エラーです。診断へ同じ値が渡ったかを `marker` で見分けます。
    private struct MarkedFailure: Error, Equatable {
        /// エラーを見分ける印です。
        let marker: String
    }

    // MARK: - prepare

    /// 組み立てが失敗したら、元のエラーと保存先の種類を診断へ1件残し、利用不能な値を返します。
    ///
    /// 責務: 失敗を成功へ潰さず、元のエラーを捨てないことを保存先の種類ごとに確認します。
    func testPrepareFailureRecordsOriginalErrorOnceAndReturnsUnavailable() {
        for storage in ProductDatabaseStorageKind.allCases {
            let spy = ProductDatabasePreparationDiagnosticsSpy()
            let factory = ProductDatabaseRepositoryFactory(diagnostics: spy)

            let value = factory.prepare(storage) { () throws -> String in
                throw MarkedFailure(marker: storage.rawValue)
            } unavailable: {
                "unavailable"
            }

            XCTAssertEqual(value, "unavailable", "保存先: \(storage)")
            XCTAssertEqual(spy.entries.map(\.storage), [storage])
            XCTAssertEqual(spy.entries.first?.error as? MarkedFailure, MarkedFailure(marker: storage.rawValue))
        }
    }

    /// 組み立てが成功したら、その値を返し、診断を残さず、利用不能な値も作りません。
    ///
    /// 責務: 成功時に診断が記録されないことを確認します。
    func testPrepareSuccessReturnsBuiltValueWithoutDiagnostics() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        var unavailableCount = 0

        let value = ProductDatabaseRepositoryFactory(diagnostics: spy).prepare(.connectionSessions) {
            "built"
        } unavailable: {
            unavailableCount += 1
            return "unavailable"
        }

        XCTAssertEqual(value, "built")
        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertEqual(unavailableCount, 0)
    }

    // MARK: - 開けない製品DB

    /// 製品DBを開けなければ、PID定義は利用不能な Repository になり、診断が1件残ります。
    ///
    /// 責務: 開けなかった元のエラーが `.obdPIDDefinitions` として残り、返った Repository の操作が失敗することを確認します。
    func testOBDPIDDefinitionRepositoryFallsBackToUnavailableWhenDatabaseCannotOpen() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeOBDPIDDefinitionRepository(database: unopenableDatabase())

        XCTAssertTrue(repository is UnavailableOBDPIDDefinitionRepository)
        assertSingleOpenFailure(in: spy, storage: .obdPIDDefinitions)
        XCTAssertThrowsError(try repository.definitions())
        XCTAssertThrowsError(try repository.definition(service: 0x01, pid: 0x0C))
    }

    /// 製品DBを開けなければ、車両別対応PIDは利用不能な Repository になり、診断が1件残ります。
    ///
    /// 責務: 開けなかった元のエラーが `.vehiclePIDCapabilities` として残り、返った Repository の操作が失敗することを確認します。
    func testVehiclePIDCapabilityRepositoryFallsBackToUnavailableWhenDatabaseCannotOpen() {
        let spy = ProductDatabasePreparationDiagnosticsSpy()

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeVehiclePIDCapabilityRepository(database: unopenableDatabase())

        XCTAssertTrue(repository is UnavailableVehiclePIDCapabilityRepository)
        assertSingleOpenFailure(in: spy, storage: .vehiclePIDCapabilities)
        XCTAssertThrowsError(try repository.capabilities(for: VehicleID()))
    }

    /// 製品DBを開けなければ、整備記録は利用不能な Repository になり、診断が1件残ります。
    ///
    /// 責務: 開けなかった元のエラーが `.maintenanceRecords` として残り、返った Repository の操作が `unavailable` で失敗することを確認します。
    func testMaintenanceRecordRepositoryFallsBackToUnavailableWhenDatabaseCannotOpen() async {
        let spy = ProductDatabasePreparationDiagnosticsSpy()

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeMaintenanceRecordRepository(database: unopenableDatabase())

        XCTAssertTrue(repository is UnavailableMaintenanceRecordRepository)
        assertSingleOpenFailure(in: spy, storage: .maintenanceRecords)
        let outcome = await AdapterLinkBoundedAwait.run("利用不能な整備記録の読込") { try await repository.records(for: "account") }
        AdapterLinkBoundedAwait.assertFailure(outcome, MaintenanceRepositoryError.unavailable)
    }

    // MARK: - Migration できない製品DB

    /// 開けても Migration できない製品DBでは、Migration の失敗が診断へ残り、利用不能な Repository になります。
    ///
    /// 責務: DBを開いた後の準備失敗も捨てずに診断1件へ変換することを確認します。
    func testMigrationFailureIsRecordedAndFallsBackToUnavailable() throws {
        let readonlyQueue = try makeReadonlyEmptyQueue()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { readonlyQueue })
        let spy = ProductDatabasePreparationDiagnosticsSpy()

        let repository = ProductDatabaseRepositoryFactory(diagnostics: spy).makeOBDPIDDefinitionRepository(database: database)

        XCTAssertTrue(repository is UnavailableOBDPIDDefinitionRepository)
        XCTAssertEqual(spy.entries.map(\.storage), [.obdPIDDefinitions])
        XCTAssertNil(spy.entries.first?.error as? MarkedFailure)
    }

    // MARK: - 開ける製品DB

    /// 製品DBを開ければ、3つとも実 Repository が返り、診断は残りません。
    ///
    /// 責務: 成功時に利用不能へ差し替えず、診断を記録しないことを確認します。
    func testOpenableDatabaseReturnsGRDBRepositoriesWithoutDiagnostics() throws {
        let queue = try DatabaseQueue()
        let database = ApplicationDatabaseConnection(openDatabaseQueue: { queue })
        let spy = ProductDatabasePreparationDiagnosticsSpy()
        let factory = ProductDatabaseRepositoryFactory(diagnostics: spy)

        let definitions = factory.makeOBDPIDDefinitionRepository(database: database)
        let capabilities = factory.makeVehiclePIDCapabilityRepository(database: database)
        let maintenance = factory.makeMaintenanceRecordRepository(database: database)

        XCTAssertTrue(definitions is GRDBOBDPIDDefinitionRepository)
        XCTAssertTrue(capabilities is GRDBVehiclePIDCapabilityRepository)
        XCTAssertTrue(maintenance is GRDBMaintenanceRecordRepository)
        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertFalse(try definitions.definitions().isEmpty, "確認済みseedが登録されていません")
    }

    // MARK: - Helpers

    /// 開けなかった製品DB接続を作ります。
    ///
    /// 責務: 開く処理が `MarkedFailure(marker: "open")` で失敗した接続を返します。
    /// - Returns: 開けなかった失敗を保持する製品DB接続。
    private func unopenableDatabase() -> ApplicationDatabaseConnection {
        ApplicationDatabaseConnection(openDatabaseQueue: { throw MarkedFailure(marker: "open") })
    }

    /// 診断が指定の保存先について1件だけ、開けなかった元のエラーで残ったことを確かめます。
    ///
    /// 責務: 件数・保存先の種類・元のエラーの3点を検証します。
    /// - Parameters:
    ///   - spy: 診断の記録先。
    ///   - storage: 期待する保存先の種類。
    private func assertSingleOpenFailure(
        in spy: ProductDatabasePreparationDiagnosticsSpy,
        storage: ProductDatabaseStorageKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(spy.entries.map(\.storage), [storage], file: file, line: line)
        XCTAssertEqual(spy.entries.first?.error as? MarkedFailure, MarkedFailure(marker: "open"), file: file, line: line)
    }

    /// 読取専用で開いた空のSQLiteファイルのQueueを作ります。
    ///
    /// 責務: 開けるが Migration できない製品DBを用意し、テスト終了時に削除します。
    /// - Returns: 読取専用のDB Queue。
    private func makeReadonlyEmptyQueue() throws -> DatabaseQueue {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ProductDatabaseRepositoryFactoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "empty.sqlite").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: nil))
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: path, configuration: configuration)
    }
}
