import Foundation

/// テストで作った ZIP を一時ファイルへ書き、テストの後で消すための置き場です。
@MainActor
final class JARTICArchiveTemporaryFiles {
    /// 一時ファイルのフォルダです。
    let directory: URL

    /// 責務: 一意な一時フォルダを作ります。
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("JARTICArchiveReader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 責務: バイト列を一時ファイルへ書き、その URL を返します。
    func write(_ bytes: [UInt8]) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).zip")
        try Data(bytes).write(to: url)
        return url
    }

    /// 責務: 一時フォルダを消します。
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
