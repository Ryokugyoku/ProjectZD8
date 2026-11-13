import CloudKit
import XCTest
@testable import ProjectZD8

/// 同期エンジンのうち、CloudKitに接続せずに確認できる部分を検証します。
///
/// `start()` は `CKContainer` を生成するため、エンタイトルメントの無いテストホストでは呼びません。
final class CloudKitSyncEngineTests: XCTestCase {
    /// 責務: アカウント状態から利用不可の理由への変換を確認します。
    func testUnavailableReasonMapping() {
        XCTAssertNil(CloudKitSyncEngine.unavailableReason(for: .available))
        XCTAssertEqual(CloudKitSyncEngine.unavailableReason(for: .noAccount), .noAccount)
        XCTAssertEqual(CloudKitSyncEngine.unavailableReason(for: .restricted), .restricted)
        XCTAssertEqual(CloudKitSyncEngine.unavailableReason(for: .couldNotDetermine), .temporarilyUnavailable)
        XCTAssertEqual(CloudKitSyncEngine.unavailableReason(for: .temporarilyUnavailable), .temporarilyUnavailable)
    }

    /// 責務: 開始前のエンジンは一時的に利用不可を報告し、送受信を型付きの失敗で拒否することを確認します。
    func testEngineBeforeStartReportsUnavailableAndRejectsSync() async throws {
        let engine = CloudKitSyncEngine(database: try AppDatabaseTesting.makeDatabase(), photoFiles: SyncTestFixtures.photoStore())
        var iterator = engine.statusUpdates().makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .unavailable(.temporarilyUnavailable))
        do {
            try await engine.syncNow()
            XCTFail("開始前の同期は失敗するはずです")
        } catch {
            XCTAssertEqual(error as? CloudSyncFailure, .other)
        }
    }
}
