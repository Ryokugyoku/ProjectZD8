import Foundation

/// 写真の画像本体を `Photos/<写真ID>.jpg` として読み書きします。永続化と同期が共有します。
nonisolated struct PhotoFileStore: Sendable {
    /// 写真ファイルを置くディレクトリです。
    let directory: URL

    /// 責務: 指定ディレクトリを写真の保存先として使うストアを生成します。
    init(directory: URL) {
        self.directory = directory
    }

    /// 責務: アプリの永続化ディレクトリ配下の写真ストアを返します。
    static func application() throws -> PhotoFileStore {
        PhotoFileStore(directory: try AppDatabase.applicationDirectory().appending(path: "Photos", directoryHint: .isDirectory))
    }

    /// 責務: 写真IDに対応するファイルURLを返します。
    func url(for id: PhotoID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString.lowercased()).jpg")
    }

    /// 責務: 画像データをアトミックに書き込みます。
    func write(_ data: Data, for id: PhotoID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: .atomic)
    }

    /// 責務: 画像データを読み込みます。ファイルが無ければ `nil` を返します。
    func read(_ id: PhotoID) throws -> Data? {
        let url = url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// 責務: 画像ファイルを削除します。無い場合は何もしません。
    func remove(_ id: PhotoID) throws {
        let url = url(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
