import Foundation
@testable import ProjectZD8

/// 配布元(一覧とダウンロード)の偽物です。一覧・ダウンロード・失敗を注入でき、呼ばれた回数と作った一時ファイルを記録します。
///
/// ダウンロードは指定の大きさの一時ファイルを本当に作り、`removeDownloadedArchive(at:)` で本当に消します。
/// 一覧とダウンロードは門(`catalogGate` / `downloadGate`)で止められます。
nonisolated final class RoadRegulationSourceFake: RoadRegulationSourcePort, @unchecked Sendable {
    /// 呼び出しを全体の順に記録する帳面です。
    let log: RoadRegulationImportCallLog
    /// 一時ファイルを作るフォルダです。
    let downloadDirectory: URL
    /// ダウンロードで作るファイルの大きさ(バイト)です。
    let archiveByteCount: Int
    /// 一覧の取得を止める門です。
    let catalogGate = RoadRegulationTestGate()
    /// ダウンロードを止める門です(最初の進捗を通知した後で止まります)。
    let downloadGate = RoadRegulationTestGate()

    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、一覧の結果です。
    private var catalogResult: Result<RoadRegulationCatalog, RoadRegulationImportError>
    /// ロックで保護した、ダウンロードで投げるエラーです。
    private var downloadError: RoadRegulationImportError?
    /// ロックで保護した、一覧の取得回数です。
    private var storedCatalogCallCount = 0
    /// ロックで保護した、ダウンロードを頼まれた一覧の行です。
    private var storedDownloadedEntries: [RoadRegulationCatalogEntry] = []
    /// ロックで保護した、作った一時ファイルです。
    private var storedCreatedURLs: [URL] = []
    /// ロックで保護した、削除を頼まれたファイルです。
    private var storedRemovedURLs: [URL] = []
    /// ロックで保護した、残ったダウンロードの掃除の回数です。
    private var storedLeftoverRemovalCount = 0

    /// 責務: 一覧と、ダウンロードで作るファイルの大きさを指定して偽物を作ります。
    /// - Parameters:
    ///   - catalog: `currentCatalog()` が返す一覧。
    ///   - downloadDirectory: 一時ファイルを作るフォルダ(テストが作って消す)。
    ///   - archiveByteCount: ダウンロードで作るファイルの大きさ。
    ///   - log: 呼び出しの帳面。
    init(catalog: RoadRegulationCatalog, downloadDirectory: URL, archiveByteCount: Int = 1_000, log: RoadRegulationImportCallLog) {
        catalogResult = .success(catalog)
        self.downloadDirectory = downloadDirectory
        self.archiveByteCount = archiveByteCount
        self.log = log
    }

    /// 責務: 一覧の取得を、指定のエラーで失敗させます。
    func failCatalog(with error: RoadRegulationImportError) {
        lock.withLock { catalogResult = .failure(error) }
    }

    /// 責務: 一覧の取得が返す一覧を差し替えます。
    func replaceCatalog(with catalog: RoadRegulationCatalog) {
        lock.withLock { catalogResult = .success(catalog) }
    }

    /// 責務: ダウンロードを、指定のエラーで失敗させます(`nil` で成功に戻します)。
    func failDownload(with error: RoadRegulationImportError?) {
        lock.withLock { downloadError = error }
    }

    /// 一覧の取得回数です。
    var catalogCallCount: Int { lock.withLock { storedCatalogCallCount } }
    /// ダウンロードを頼まれた一覧の行です(頼まれた順)。
    var downloadedEntries: [RoadRegulationCatalogEntry] { lock.withLock { storedDownloadedEntries } }
    /// 作った一時ファイルです。
    var createdURLs: [URL] { lock.withLock { storedCreatedURLs } }
    /// 削除を頼まれたファイルです。
    var removedURLs: [URL] { lock.withLock { storedRemovedURLs } }
    /// 残ったダウンロードの掃除の回数です。
    var leftoverRemovalCount: Int { lock.withLock { storedLeftoverRemovalCount } }

    /// 作った一時ファイルのうち、まだ残っているものです。
    var remainingFiles: [URL] {
        createdURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 責務: 一覧の取得を記録し、門が開くのを待ってから、注入された結果を返します。
    func currentCatalog() async throws -> RoadRegulationCatalog {
        log.record(.fetchCatalog)
        lock.withLock { storedCatalogCallCount += 1 }
        try await catalogGate.waitAsync()
        return try lock.withLock { catalogResult }.get()
    }

    /// 責務: ダウンロードを記録し、最初の進捗を通知し、門が開いたら一時ファイルを作って残りの進捗を通知します。
    func downloadArchive(
        for entry: RoadRegulationCatalogEntry,
        progress: @escaping @Sendable (RoadRegulationTransferProgress) -> Void
    ) async throws -> URL {
        log.record(.download)
        let error = lock.withLock { () -> RoadRegulationImportError? in
            storedDownloadedEntries.append(entry)
            return downloadError
        }
        if let error { throw error }
        let total = Int64(archiveByteCount)
        progress(RoadRegulationTransferProgress(receivedBytes: 0, expectedBytes: total))
        try await downloadGate.waitAsync()
        let url = try writeArchiveFile()
        progress(RoadRegulationTransferProgress(receivedBytes: total / 2, expectedBytes: total))
        progress(RoadRegulationTransferProgress(receivedBytes: total, expectedBytes: total))
        return url
    }

    /// 責務: 削除を記録し、ファイルを本当に消します(失敗は無視)。
    func removeDownloadedArchive(at url: URL) {
        log.record(.removeDownloadedArchive)
        lock.withLock { storedRemovedURLs.append(url) }
        try? FileManager.default.removeItem(at: url)
    }

    /// 責務: 残ったダウンロードの掃除を記録します。
    func removeLeftoverDownloads() {
        log.record(.removeLeftoverDownloads)
        lock.withLock { storedLeftoverRemovalCount += 1 }
    }

    /// 責務: 指定の大きさの一時ファイルを作り、作ったことを記録します。
    private func writeArchiveFile() throws -> URL {
        let url = downloadDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try Data(count: archiveByteCount).write(to: url)
        lock.withLock { storedCreatedURLs.append(url) }
        return url
    }
}
