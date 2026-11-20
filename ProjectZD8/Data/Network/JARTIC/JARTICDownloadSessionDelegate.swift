import Foundation

/// ダウンロードの進捗・リダイレクトの制限・完了を、呼び出し側へ橋渡しする delegate です。
nonisolated final class JARTICDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationDirectory: URL
    private let allowedHost: String
    private let progress: @Sendable (RoadRegulationTransferProgress) -> Void
    private let completion: @Sendable (Result<URL, RoadRegulationImportError>) -> Void
    private let lock = NSLock()
    private var outcome: Result<URL, RoadRegulationImportError>?
    private var didComplete = false

    /// delegate を作ります。
    ///
    /// 責務: 保存先・許可するホスト・通知先を保持します。
    /// - Parameters:
    ///   - destinationDirectory: 受け取ったファイルを移す先のフォルダ。
    ///   - allowedHost: リダイレクトを許すホスト名。
    ///   - progress: 受信バイト数と全体の大きさの通知先。
    ///   - completion: 完了(保存先のファイルまたは失敗)の通知先。ちょうど1回だけ呼びます。
    init(destinationDirectory: URL, allowedHost: String,
         progress: @escaping @Sendable (RoadRegulationTransferProgress) -> Void,
         completion: @escaping @Sendable (Result<URL, RoadRegulationImportError>) -> Void) {
        self.destinationDirectory = destinationDirectory
        self.allowedHost = allowedHost
        self.progress = progress
        self.completion = completion
    }

    /// 受信の進み具合を通知します。
    ///
    /// 責務: 受信バイト数と全体の大きさ(不明なら `nil`)を `progress` へ渡します。
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        progress(RoadRegulationTransferProgress(receivedBytes: totalBytesWritten, expectedBytes: expected))
    }

    /// 同じホストへの https のリダイレクトだけを許します。
    ///
    /// 責務: 許可外の移動先なら追従せず、元の応答(成功でない状態)を受け取ります。
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.host == allowedHost else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    /// 一時ファイルを保存先へ移します。
    ///
    /// 責務: 状態が成功で、途中で切れていない時だけ、ファイルを移して結果を記録します。
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !isTruncated(downloadTask) else {
            record(.failure(.downloadFailed))
            return
        }
        let destination = destinationDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            record(.success(destination))
        } catch {
            record(.failure(.downloadFailed))
        }
    }

    /// タスクの終了を通知します。
    ///
    /// 責務: エラーがあれば失敗、無ければ記録済みの結果を `completion` へ1回だけ渡します。
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let recorded = outcome
        let alreadyCompleted = didComplete
        didComplete = true
        lock.unlock()
        guard !alreadyCompleted else { return }
        if error != nil {
            if case .success(let file)? = recorded { try? FileManager.default.removeItem(at: file) }
            completion(.failure(.downloadFailed))
        } else {
            completion(recorded ?? .failure(.downloadFailed))
        }
    }

    /// 予定の大きさより少ない受信を途中切れとみなします。
    private func isTruncated(_ task: URLSessionTask) -> Bool {
        let expected = task.countOfBytesExpectedToReceive
        return expected > 0 && task.countOfBytesReceived < expected
    }

    /// 結果を記録します(完了通知は `didCompleteWithError` で行う)。
    private func record(_ result: Result<URL, RoadRegulationImportError>) {
        lock.lock()
        outcome = result
        lock.unlock()
    }
}
