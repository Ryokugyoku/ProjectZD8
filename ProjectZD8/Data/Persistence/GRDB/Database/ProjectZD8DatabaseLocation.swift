import Foundation
import GRDB

/// 製品版SQLite DBの保存先を一元的に解決します。
enum ProjectZD8DatabaseLocation {
    /// 製品DBを格納するディレクトリ名です。
    static let directoryName = "ProjectZD8"
    /// 製品DBのファイル名です。
    static let fileName = "projectzd8.sqlite"

    /// 指定した基底ディレクトリ配下に製品DB用ディレクトリを作成してDBファイルURLを返します。
    ///
    /// 責務: `<base>/ProjectZD8/` を中間ディレクトリ込みで作成し、その中の製品DBファイルURLへ変換します。
    /// - Parameters:
    ///   - baseDirectory: 製品DB用ディレクトリを作成する基底ディレクトリ。
    ///   - fileManager: ディレクトリ作成に使用するFileManager。
    /// - Returns: `<base>/ProjectZD8/projectzd8.sqlite` のファイルURL。
    /// - Throws: ディレクトリを作成できない場合のFileManagerエラー。
    static func prepareDatabaseFileURL(in baseDirectory: URL, fileManager: FileManager) throws -> URL {
        let directory = baseDirectory.appending(path: directoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }

    /// 指定した基底ディレクトリ配下の製品DBを開きます。
    ///
    /// 責務: 製品DB用ディレクトリを準備し、その中のDBファイルへの未Migration接続を返します。
    /// - Parameters:
    ///   - baseDirectory: 製品DB用ディレクトリを作成する基底ディレクトリ。
    ///   - fileManager: ディレクトリ作成に使用するFileManager。
    /// - Returns: 製品DBファイルへ接続したDB Queue。Migrationは呼び出し側Repositoryが適用します。
    /// - Throws: ディレクトリ作成またはDB接続に失敗した場合のエラー。
    static func openDatabaseQueue(in baseDirectory: URL, fileManager: FileManager) throws -> DatabaseQueue {
        let fileURL = try prepareDatabaseFileURL(in: baseDirectory, fileManager: fileManager)
        return try DatabaseQueue(path: fileURL.path)
    }

    /// Application Support内の製品DBを開きます。
    ///
    /// 責務: ユーザー領域のApplication Supportを解決して製品DBファイルへの未Migration接続を返します。
    /// - Returns: 製品DBファイルへ接続したDB Queue。Migrationは呼び出し側Repositoryが適用します。
    /// - Throws: Application Support解決、ディレクトリ作成、DB接続に失敗した場合のエラー。
    static func openApplicationDatabaseQueue() throws -> DatabaseQueue {
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try openDatabaseQueue(in: support, fileManager: fileManager)
    }
}
