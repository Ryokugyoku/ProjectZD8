import CloudKit
import Foundation

/// `CKContainer` の private database で `CloudKitPrivateRecordStore` を実現します。
///
/// クエリの最初のページが「レコードタイプが存在しない」(`CKError.unknownItem`)で失敗した場合だけ、空の結果を返します。
/// 存在しないタイプのレコードは1件も存在し得ないので、空は事実として正しく、失敗を潰すことにはなりません。
/// これをしないと、本番スキーマの反映前に `deleteAll` が失敗し、アカウント削除が完了しなくなります。
/// 判定は `CloudKitMissingRecordTypePolicy` に従い、ほかの失敗と2ページ目以降の失敗は包まずに投げます。
/// 返るコードが `unknownItem` であることは、実機と CloudKit の環境での確認が必要です。
@MainActor
final class CKDatabasePrivateRecordStore: CloudKitPrivateRecordStore {
    /// クエリを続けるページ数の上限です。超えた場合は異常として失敗にします。
    static let maximumQueryPageCount = 1_000

    /// テストまたは明示の構成で使う CloudKit コンテナです。`nil` なら利用時に既定のコンテナを使います。
    private let injectedContainer: CKContainer?
    /// クエリの失敗がレコードタイプの不在かを判定する規則です。
    private let missingRecordTypePolicy = CloudKitMissingRecordTypePolicy()

    /// クエリ1ページ分の結果です。
    private typealias QueryPage = (
        matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
        queryCursor: CKQueryOperation.Cursor?
    )

    /// コンテナを固定して作ります。CloudKit にはまだ触れません。
    ///
    /// 責務: private database の取得先を、利用時まで遅らせて保持します。
    /// 値を保持するだけなので隔離せず、リポジトリの init の既定引数からも作れるようにします。
    /// - Parameter container: private database を提供するコンテナ。`nil` は `CKContainer.default()`。
    nonisolated init(container: CKContainer? = nil) {
        injectedContainer = container
    }

    /// 1件のレコードを取得します。
    ///
    /// 責務: 指定 ID の取得結果を、存在しなければ `nil` に変えて返します。
    /// - Parameters:
    ///   - id: 取得するレコード ID。
    ///   - desiredKeys: 取得するフィールド。`nil` は全フィールド。
    /// - Returns: レコード。`unknownItem` の場合は `nil`。
    /// - Throws: それ以外の CloudKit の失敗。結果が返らない場合は `ConnectionSessionRepositoryError.invalidState`。
    func record(for id: CKRecord.ID, desiredKeys: [CKRecord.FieldKey]?) async throws -> CKRecord? {
        do {
            let results = try await privateDatabase.records(for: [id], desiredKeys: desiredKeys)
            guard let result = results[id] else {
                throw ConnectionSessionRepositoryError.invalidState
            }
            return try result.get()
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// レコードを全フィールドで上書き保存します。
    ///
    /// 責務: `savePolicy = .allKeys` で1件を保存し、そのレコードの結果を確かめます。
    /// - Parameter record: 保存するレコード。
    /// - Throws: CloudKit の保存の失敗。結果が返らない場合は `ConnectionSessionRepositoryError.invalidState`。
    func overwrite(_ record: CKRecord) async throws {
        let results = try await privateDatabase.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys
        )
        guard let result = results.saveResults[record.recordID] else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        _ = try result.get()
    }

    /// フィールドの一致で絞ったレコードを全ページ取得します。
    ///
    /// 責務: 最初のページとカーソルによる続きのページを、上限のページ数まで集めます。
    /// - Parameters:
    ///   - recordType: 取得するレコードタイプ。
    ///   - field: 比べるフィールド。
    ///   - value: 等しいとみなす値。
    ///   - desiredKeys: 取得するフィールド。続きのページにも同じ指定を使います。
    /// - Returns: 一致したすべてのレコード。
    /// - Throws: CloudKit のクエリの失敗。ページ数が上限を超えた場合は `ConnectionSessionRepositoryError.invalidState`。
    func records(
        ofType recordType: String,
        whereField field: CKRecord.FieldKey,
        equals value: String,
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(format: "%K == %@", field, value))
        guard var page = try await firstPage(of: query, desiredKeys: desiredKeys) else {
            return []
        }
        var output = try Self.records(in: page.matchResults)
        for _ in 1..<Self.maximumQueryPageCount {
            guard let cursor = page.queryCursor else {
                return output
            }
            page = try await privateDatabase.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys)
            output.append(contentsOf: try Self.records(in: page.matchResults))
        }
        guard page.queryCursor == nil else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        return output
    }

    /// レコードがあれば削除します。
    ///
    /// 責務: 1件を削除し、`unknownItem` は成功として扱います。
    /// - Parameter id: 削除するレコード ID。
    /// - Throws: それ以外の CloudKit の削除の失敗。
    func deleteRecordIfPresent(_ id: CKRecord.ID) async throws {
        do {
            _ = try await privateDatabase.deleteRecord(withID: id)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    /// クエリの最初のページを取得します。
    ///
    /// 責務: レコードタイプが存在しない失敗だけを `nil`(空の結果)に変え、ほかの失敗は包まずに投げます。
    /// 存在しないタイプのレコードは1件も存在し得ないので、空は事実として正しい結果です。これをしないと、
    /// 本番スキーマの反映前に `deleteAll` が失敗し、アカウント削除が完了しなくなります。
    /// 返るコードが `unknownItem` であることは、実機と CloudKit の環境での確認が必要です。
    /// - Parameters:
    ///   - query: 実行するクエリ。
    ///   - desiredKeys: 取得するフィールド。
    /// - Returns: 最初のページ。レコードタイプが存在しなければ `nil`。
    /// - Throws: それ以外の CloudKit の失敗。
    private func firstPage(
        of query: CKQuery,
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> QueryPage? {
        do {
            return try await privateDatabase.records(matching: query, desiredKeys: desiredKeys)
        } catch where missingRecordTypePolicy.isMissingRecordType(error) {
            return nil
        }
    }

    /// 1ページ分のクエリ結果からレコードを取り出します。
    ///
    /// 責務: レコードごとの失敗を包まずに投げ、成功したレコードだけを並べます。
    /// - Parameter matchResults: 1ページ分の結果。
    /// - Returns: そのページのレコード。
    /// - Throws: レコードごとの CloudKit の失敗。
    private static func records(
        in matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)]
    ) throws -> [CKRecord] {
        try matchResults.map { try $0.1.get() }
    }

    /// 利用時に解決する CloudKit の private database です。
    private var privateDatabase: CKDatabase {
        (injectedContainer ?? CKContainer.default()).privateCloudDatabase
    }
}
