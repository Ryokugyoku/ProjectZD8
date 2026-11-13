import CloudKit
import Foundation
import Synchronization

/// アーカイブゾーンの `RTSessionArchive` レコードのアセットと検証値を、進捗付きでダウンロードします。
nonisolated struct CloudKitArchiveDownloader: Sendable {
    /// ダウンロードしたアーカイブと、レコードに記録された検証値です。
    nonisolated struct Download: Sendable {
        let data: Data
        let digest: String
    }

    private let database: CKDatabase

    /// 責務: 指定データベースからダウンロードする取得器を生成します。
    init(database: CKDatabase) {
        self.database = database
    }

    /// 責務: レコードのアーカイブのアセットと検証値を取得します。
    /// - Throws: CloudKitのエラー、またはアセット・検証値が無い場合は `CloudSyncFailure.notFound`。
    func download(recordID: CKRecord.ID, progress: @escaping @Sendable (Double) -> Void) async throws -> Download {
        let result = CloudKitArchiveDownloadResultBox()
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [recordID])
            operation.desiredKeys = [CloudKitArchiveRecordMapper.Field.archive, CloudKitArchiveRecordMapper.Field.archiveDigest]
            operation.qualityOfService = .userInitiated
            operation.perRecordProgressBlock = { _, fraction in
                progress(fraction)
            }
            operation.perRecordResultBlock = { _, recordResult in
                // アセットの一時ファイルは操作の完了後に消えるため、ここで読み込みます。
                let outcome: Result<Download, any Error> = recordResult.flatMap { record in
                    guard let asset = record[CloudKitArchiveRecordMapper.Field.archive] as? CKAsset,
                          let url = asset.fileURL,
                          let digest = record[CloudKitArchiveRecordMapper.Field.archiveDigest] as? String else {
                        return .failure(CloudSyncFailure.notFound)
                    }
                    return Result { Download(data: try Data(contentsOf: url), digest: digest) }
                }
                result.value.withLock { $0 = outcome }
            }
            operation.fetchRecordsResultBlock = { operationResult in
                switch operationResult {
                case .failure(let error):
                    let recordError = result.value.withLock { stored -> (any Error)? in
                        if case .failure(let error) = stored { return error }
                        return nil
                    }
                    continuation.resume(throwing: recordError ?? error)
                case .success:
                    let stored = result.value.withLock { $0 }
                    continuation.resume(with: stored ?? .failure(CloudSyncFailure.notFound))
                }
            }
            database.add(operation)
        }
    }
}

/// 操作のコールバック間でダウンロード結果を受け渡す入れ物です。
private nonisolated final class CloudKitArchiveDownloadResultBox: Sendable {
    let value = Mutex<Result<CloudKitArchiveDownloader.Download, any Error>?>(nil)
}
