import XCTest
@testable import ProjectZD8

/// 同期エンジンの状態の保存を確認します。
final class SyncEngineStateStoreTests: XCTestCase {
    /// 責務: 保存・読み込み・消去が往復することを確認します。
    func testSaveLoadAndClear() throws {
        let store = SyncEngineStateStore(database: try AppDatabaseTesting.makeDatabase())
        XCTAssertNil(try store.load())
        try store.save(Data([1, 2]))
        try store.save(Data([3]))
        XCTAssertEqual(try store.load(), Data([3]))
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
