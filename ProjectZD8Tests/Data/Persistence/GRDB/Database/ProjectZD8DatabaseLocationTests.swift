import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品DB保存先URLの解決とディレクトリ作成を一時ディレクトリで検証します。
final class ProjectZD8DatabaseLocationTests: XCTestCase {
    /// テストごとに作る一時基底ディレクトリです。
    private var temporaryRoot: URL!

    /// 一意な一時ディレクトリパスを決めます。
    ///
    /// 責務: テスト間で干渉しない基底パスを用意します(ディレクトリ自体は作成しません)。
    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "ProjectZD8DatabaseLocationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// 一時ディレクトリを削除します。
    ///
    /// 責務: テストが作成したファイルとディレクトリを残さないことを保証します。
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryRoot.path) {
            try FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    /// 識別名定数が製品仕様の値であることを確認します。
    ///
    /// 責務: 既存ユーザーDBの保存先を変える名称変更を検出します。
    func testNamesMatchProductDatabaseLocation() {
        XCTAssertEqual(ProjectZD8DatabaseLocation.directoryName, "ProjectZD8")
        XCTAssertEqual(ProjectZD8DatabaseLocation.fileName, "projectzd8.sqlite")
    }

    /// 存在しない入れ子の基底配下でも中間ディレクトリごと作成します。
    ///
    /// 責務: 返却URLの構成と、DBファイル自体は作らずディレクトリだけ作ることを確認します。
    func testCreatesMissingIntermediateDirectoriesAndReturnsExactURL() throws {
        let base = temporaryRoot.appending(path: "a/b/c", directoryHint: .isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))

        let url = try ProjectZD8DatabaseLocation.prepareDatabaseFileURL(in: base, fileManager: .default)

        XCTAssertEqual(url.lastPathComponent, "projectzd8.sqlite")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ProjectZD8")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL, base.standardizedFileURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// 既存ディレクトリに対する再実行が成功し同じURLを返します。
    ///
    /// 責務: 起動のたびに呼ばれても失敗せず、既存DBファイルを壊さないことを確認します。
    func testIsIdempotentWhenDirectoryAlreadyExists() throws {
        let first = try ProjectZD8DatabaseLocation.prepareDatabaseFileURL(in: temporaryRoot, fileManager: .default)
        let marker = Data("existing".utf8)
        try marker.write(to: first)

        let second = try ProjectZD8DatabaseLocation.prepareDatabaseFileURL(in: temporaryRoot, fileManager: .default)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), marker)
    }

    /// 保存先名のパスに通常ファイルがある場合は作成失敗を投げます。
    ///
    /// 責務: ディレクトリを作れない状態を成功へ潰さないことを確認します。
    func testThrowsWhenRegularFileOccupiesDirectoryName() throws {
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let blocker = temporaryRoot.appending(path: ProjectZD8DatabaseLocation.directoryName)
        try Data("not a directory".utf8).write(to: blocker)

        XCTAssertThrowsError(
            try ProjectZD8DatabaseLocation.prepareDatabaseFileURL(in: temporaryRoot, fileManager: .default)
        )
        var isDirectory: ObjCBool = true
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocker.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
    }

    /// 未作成の基底配下で製品DB接続を開きます。
    ///
    /// 責務: 返却Queueが製品DBパスを指し、ディレクトリ作成と書込み後のファイル存在を確認します。
    func testOpenDatabaseQueueCreatesDirectoriesAndOpensProductFile() throws {
        let base = temporaryRoot.appending(path: "x/y", directoryHint: .isDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))

        let queue = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: base, fileManager: .default)
        try queue.write { try $0.execute(sql: "CREATE TABLE probe (id INTEGER PRIMARY KEY)") }

        let expected = base.appending(path: "ProjectZD8").appending(path: "projectzd8.sqlite")
        XCTAssertEqual(
            URL(fileURLWithPath: queue.path).resolvingSymlinksInPath().path,
            expected.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        let tableExists = try queue.read { try $0.tableExists("probe") }
        XCTAssertTrue(tableExists)
    }

    /// 既存DBファイルの内容を再オープンで保持します。
    ///
    /// 責務: 2回目の接続が同じファイルを開き、先に書いたデータを読めることを確認します。
    func testOpenDatabaseQueueReopensExistingDatabaseWithData() throws {
        let first = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)
        try first.write { database in
            try database.execute(sql: "CREATE TABLE probe (value TEXT)")
            try database.execute(sql: "INSERT INTO probe VALUES ('kept')")
        }

        let second = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)
        let value = try second.read { try String.fetchOne($0, sql: "SELECT value FROM probe") }

        XCTAssertEqual(value, "kept")
        XCTAssertEqual(first.path, second.path)
    }

    /// ディレクトリを作れない場合はDB接続を開かず失敗を伝播します。
    ///
    /// 責務: 保存先名に通常ファイルがあるとき作成エラーを投げDBファイルを作らないことを確認します。
    func testOpenDatabaseQueuePropagatesDirectoryCreationFailure() throws {
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let blocker = temporaryRoot.appending(path: ProjectZD8DatabaseLocation.directoryName)
        try Data("not a directory".utf8).write(to: blocker)

        XCTAssertThrowsError(
            try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)
        )
        let contents = try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path)
        XCTAssertEqual(contents, [ProjectZD8DatabaseLocation.directoryName])
    }

    /// ファイルDBを開いた直後の接続設定が仕様どおりです。
    ///
    /// 責務: 製品DBの `journal_mode=wal`、`synchronous=1(NORMAL)`、`foreign_keys=1` を実PRAGMAで確認します。
    func testOpenDatabaseQueueAppliesWALNormalSynchronousAndForeignKeys() throws {
        let queue = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)

        let pragmas = try queue.read { database in
            (
                journalMode: try String.fetchOne(database, sql: "PRAGMA journal_mode"),
                synchronous: try Int.fetchOne(database, sql: "PRAGMA synchronous"),
                foreignKeys: try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
            )
        }

        XCTAssertEqual(pragmas.journalMode, "wal")
        XCTAssertEqual(pragmas.synchronous, 1)
        XCTAssertEqual(pragmas.foreignKeys, 1)
    }

    /// 再オープンしても接続設定が維持されます。
    ///
    /// 責務: 既存DBファイルを開き直した接続にもWAL・NORMAL・外部キー有効が適用されることを確認します。
    func testReopenedDatabaseQueueKeepsConnectionSettings() throws {
        _ = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)

        let reopened = try ProjectZD8DatabaseLocation.openDatabaseQueue(in: temporaryRoot, fileManager: .default)

        try reopened.read { database in
            XCTAssertEqual(try String.fetchOne(database, sql: "PRAGMA journal_mode"), "wal")
            XCTAssertEqual(try Int.fetchOne(database, sql: "PRAGMA synchronous"), 1)
            XCTAssertEqual(try Int.fetchOne(database, sql: "PRAGMA foreign_keys"), 1)
        }
    }
}
