import Foundation
import GRDB

/// アプリ全体で1つだけ開くSQLiteデータベースです。全リポジトリと同期がこの1接続を共有します。
nonisolated final class AppDatabase: Sendable {
    /// 読み書きに使う共有接続です。
    let writer: any DatabaseWriter

    /// 既に開いた接続へスキーマを適用して包みます。
    ///
    /// 責務: 接続へ現行スキーマを適用します。
    /// - Throws: スキーマを適用できない場合のデータベースエラー。
    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try AppDatabaseMigrator.migrator.migrate(writer)
    }

    /// アプリの保存先にあるデータベースを開きます。
    ///
    /// 責務: Application Support配下の本番データベースを開きます。
    /// - Throws: ディレクトリ作成または接続に失敗した場合のエラー。
    static func openApplicationDatabase() throws -> AppDatabase {
        let directory = try applicationDirectory()
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: directory.appending(path: fileName).path, configuration: configuration)
        return try AppDatabase(writer: pool)
    }

    /// テスト用のメモリ上データベースを開きます。
    ///
    /// 責務: 永続化しない空のデータベースを生成します。
    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try AppDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    /// データベースと写真を置くアプリ専用ディレクトリを返します。無ければ作成します。
    ///
    /// 責務: アプリの永続化ディレクトリを解決します。
    static func applicationDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appending(path: "ProjectZD8", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 現行スキーマのデータベースファイル名です。互換性のないスキーマへ変える時は名前を変えます。
    static let fileName = "insight-v1.sqlite"
}
