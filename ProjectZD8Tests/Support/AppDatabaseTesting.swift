import XCTest
@testable import ProjectZD8

/// テスト用のメモリ上データベースを生成します。
enum AppDatabaseTesting {
    /// 責務: 現行スキーマを適用した空のデータベースを返します。
    static func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }
}
