import Foundation

/// JARTIC の配布から一覧と ZIP を取得する `RoadRegulationSourcePort` の実装です。
nonisolated final class URLSessionJARTICRoadRegulationSource: RoadRegulationSourcePort {
    private let indexURL: URL
    private let downloadDirectory: URL
    private let configuration: URLSessionConfiguration
    private let decoder: JARTICOpenDataIndexDecoder

    /// 取得元を作ります。
    ///
    /// 責務: 一覧の URL・保存先・通信の構成・解読器を保持します(通信はまだ行いません)。
    /// - Parameters:
    ///   - indexURL: 一覧 JSON の URL。
    ///   - downloadDirectory: ダウンロードした ZIP の置き場。
    ///   - configuration: 通信の構成。テストは `URLProtocol` を差し込んだ構成を渡します。
    ///   - decoder: 一覧の解読器。
    init(indexURL: URL = URL(string: "https://www.jartic.or.jp/d/opendata/opendata.json")!,
         downloadDirectory: URL,
         configuration: URLSessionConfiguration = JARTICURLSessionConfiguration.make(),
         decoder: JARTICOpenDataIndexDecoder = .init()) {
        self.indexURL = indexURL
        self.downloadDirectory = downloadDirectory
        self.configuration = configuration
        self.decoder = decoder
    }

    /// 配布の一覧を取得します。
    ///
    /// 責務: 一覧 JSON を読み込み、解読して返します。通信の失敗は `catalogUnavailable` にします。
    /// - Returns: 解読した一覧。
    /// - Throws: `RoadRegulationImportError` または `CancellationError`。
    func currentCatalog() async throws -> RoadRegulationCatalog {
        try Task.checkCancellation()
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        do {
            let (body, response) = try await session.data(for: makeRequest(for: indexURL))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RoadRegulationImportError.catalogUnavailable
            }
            data = body
        } catch let error as RoadRegulationImportError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw RoadRegulationImportError.catalogUnavailable
        }
        return try decoder.decode(data)
    }

    /// ZIP を一時ファイルへ取得します。
    ///
    /// 責務: https の ZIP を `downloadTask` で取得し、進捗を通知し、キャンセルに応じ、失敗を `downloadFailed` に分類します。
    /// - Parameters:
    ///   - entry: 取得する項目。
    ///   - progress: 進捗の通知先。
    /// - Returns: 保存した ZIP のファイル URL。取り込みの後に `removeDownloadedArchive(at:)` で消します。
    /// - Throws: `RoadRegulationImportError` または `CancellationError`。
    func downloadArchive(for entry: RoadRegulationCatalogEntry,
                         progress: @escaping @Sendable (RoadRegulationTransferProgress) -> Void) async throws -> URL {
        try Task.checkCancellation()
        guard entry.archiveURL.scheme == "https", let host = entry.archiveURL.host else {
            throw RoadRegulationImportError.downloadFailed
        }
        let handle = JARTICDownloadTaskHandle()
        defer { handle.invalidate() }
        let request = makeRequest(for: entry.archiveURL)
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    start(request, host: host, progress: progress, handle: handle) { continuation.resume(with: $0) }
                }
            } onCancel: {
                handle.cancel()
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    /// ダウンロードした ZIP を消します。
    ///
    /// 責務: 保存先のフォルダ直下のファイルだけを消し、失敗は無視します。
    func removeDownloadedArchive(at url: URL) {
        guard url.standardizedFileURL.deletingLastPathComponent().path == downloadDirectory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 前回の取り込みで残った ZIP を消します。
    ///
    /// 責務: 保存先のフォルダの中身をすべて消し、失敗は無視します。
    func removeLeftoverDownloads() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: downloadDirectory.path)) ?? []
        for name in names {
            try? FileManager.default.removeItem(at: downloadDirectory.appendingPathComponent(name))
        }
    }

    /// 利用者の情報を含まない要求を作ります。
    ///
    /// 責務: URL をそのまま使い(クエリを足さない)、キャッシュとクッキーを使わない要求を返します。
    private func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        return request
    }

    /// セッションを作ってダウンロードを始めます。
    ///
    /// 責務: delegate 付きのセッションとタスクを作り、`handle` に登録して開始します。
    private func start(_ request: URLRequest, host: String, progress: @escaping @Sendable (RoadRegulationTransferProgress) -> Void,
                       handle: JARTICDownloadTaskHandle, completion: @escaping @Sendable (Result<URL, RoadRegulationImportError>) -> Void) {
        let delegate = JARTICDownloadSessionDelegate(destinationDirectory: downloadDirectory, allowedHost: host,
                                                     progress: progress, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        handle.register(task: task, session: session)
        task.resume()
    }
}
