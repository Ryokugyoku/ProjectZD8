import CloudKit
import Foundation

/// CloudKit の private database を差し替えるための狭い口です。
///
/// 実装は CloudKit のエラー(`CKError`)を包まずに投げます。呼び出し側(`CloudKitAccountDeletionFailureClassifier` など)が型で分類するためです。
@MainActor
protocol CloudKitPrivateRecordStore {
    /// 1件のレコードを取得します。
    ///
    /// 責務: 指定 ID のレコードを、指定したフィールドだけで返します。
    /// - Parameters:
    ///   - id: 取得するレコード ID。
    ///   - desiredKeys: 取得するフィールド。`nil` は全フィールド(Asset を含む)。
    /// - Returns: レコード。存在しない(`unknownItem`)場合は `nil`。
    /// - Throws: それ以外の CloudKit の失敗。
    func record(for id: CKRecord.ID, desiredKeys: [CKRecord.FieldKey]?) async throws -> CKRecord?

    /// レコードを、サーバー上の内容に関係なく全フィールドで上書き保存します。
    ///
    /// 責務: `savePolicy = .allKeys` で1件を保存します。
    /// - Parameter record: 保存するレコード。
    /// - Throws: CloudKit の保存の失敗。
    func overwrite(_ record: CKRecord) async throws

    /// 1つのフィールドが指定の文字列に等しいレコードを、全ページ取得します。
    ///
    /// 責務: レコードタイプとフィールドの一致で絞ったクエリを、カーソルが尽きるまで続けます。
    /// - Parameters:
    ///   - recordType: 取得するレコードタイプ。
    ///   - field: 比べるフィールド(Queryable であること)。
    ///   - value: 等しいとみなす値。
    ///   - desiredKeys: 取得するフィールド。`nil` は全フィールド。
    /// - Returns: 一致したすべてのレコード。
    /// - Throws: CloudKit のクエリの失敗。
    func records(
        ofType recordType: String,
        whereField field: CKRecord.FieldKey,
        equals value: String,
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord]

    /// レコードがあれば削除します。
    ///
    /// 責務: 1件を削除し、存在しない(`unknownItem`)場合も成功とします。
    /// - Parameter id: 削除するレコード ID。
    /// - Throws: それ以外の CloudKit の削除の失敗。
    func deleteRecordIfPresent(_ id: CKRecord.ID) async throws
}
