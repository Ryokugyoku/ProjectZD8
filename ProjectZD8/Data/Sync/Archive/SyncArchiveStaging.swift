import Foundation

/// アップロード中のアーカイブを `CKAsset` として渡すための一時ファイルを管理します。
///
/// 送信が終わるまでファイルを残す必要があるため、セッションIDごとに決まったパスへ書き出します。
nonisolated struct SyncArchiveStaging: Sendable {
    /// 一時ファイルを置くディレクトリです。
    let directory: URL

    /// 責務: 指定ディレクトリを一時置き場にします。
    init(directory: URL = FileManager.default.temporaryDirectory.appending(path: "RevTorqueInsightSyncUploads", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// 責務: セッションの一時ファイルのURLを返します。
    func url(forSessionID sessionID: String) -> URL {
        directory.appending(path: "\(sessionID).rtarchive")
    }

    /// 責務: アーカイブを一時ファイルへ書き出し、そのURLを返します。
    func write(_ archive: EncodedSessionArchive, sessionID: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(forSessionID: sessionID)
        try archive.data.write(to: url, options: .atomic)
        return url
    }

    /// 責務: セッションの一時ファイルを削除します。無ければ何もしません。
    func remove(sessionID: String) {
        try? FileManager.default.removeItem(at: url(forSessionID: sessionID))
    }
}
