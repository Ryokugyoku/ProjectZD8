import CloudKit
import Foundation
@testable import ProjectZD8

/// `CloudKitPrivateRecordStore` のメモリ上のフェイクです。CloudKit には接続しません。
///
/// 呼び出しの記録(上書きの回数、各取得の `desiredKeys`、上書き時点の Asset の場所と中身)と、
/// メソッドごとの失敗の注入を提供します。
@MainActor
final class InMemoryCloudKitPrivateRecordStore: CloudKitPrivateRecordStore {
    /// 注入する失敗です。
    enum InjectedError: Error, Equatable {
        /// 取得の失敗です。
        case fetch
        /// 上書きの失敗です。
        case overwrite
        /// 検索の失敗です。
        case query
        /// 削除の失敗です。
        case delete
    }

    /// 保持しているレコードです。
    private(set) var storedRecords: [CKRecord.ID: CKRecord] = [:]
    /// `overwrite` が呼ばれた回数です(失敗した呼び出しも数えます)。
    private(set) var overwriteCount = 0
    /// `record(for:desiredKeys:)` が受け取った `desiredKeys` の履歴です。
    private(set) var recordDesiredKeysHistory: [[CKRecord.FieldKey]?] = []
    /// `records(ofType:...)` が受け取った `desiredKeys` の履歴です。
    private(set) var queryDesiredKeysHistory: [[CKRecord.FieldKey]?] = []
    /// `records(ofType:...)` が受け取った (タイプ, フィールド, 値) の履歴です。
    private(set) var queries: [(type: String, field: String, value: String)] = []
    /// `deleteRecordIfPresent` が受け取った ID の履歴です。
    private(set) var deleteRequests: [CKRecord.ID] = []
    /// `overwrite` に渡された時点のレコードの Asset の場所です。
    private(set) var overwrittenAssetURLs: [URL] = []
    /// `overwrite` に渡された時点の Asset の中身です。
    private(set) var overwrittenAssetBytes: [Data] = []

    /// 設定すると `record(for:desiredKeys:)` が投げます。
    var fetchError: InjectedError?
    /// 設定すると `overwrite` が(記録のあとに)投げ、保存しません。
    var overwriteError: InjectedError?
    /// 設定すると `records(ofType:...)` が投げます。
    var queryError: InjectedError?
    /// 設定すると `deleteRecordIfPresent` が投げ、削除しません。
    var deleteError: InjectedError?

    /// 事前にレコードを保持させます。
    ///
    /// 責務: テストの準備として、呼び出しを数えずにレコードを辞書へ入れます。
    func seed(_ record: CKRecord) {
        storedRecords[record.recordID] = record
    }

    /// ID に対応するレコードを返します。
    ///
    /// 責務: 履歴を残し、`desiredKeys` 指定時は指定外のフィールドを落とした写しを返します。無ければ `nil`。
    func record(for id: CKRecord.ID, desiredKeys: [CKRecord.FieldKey]?) async throws -> CKRecord? {
        recordDesiredKeysHistory.append(desiredKeys)
        if let fetchError { throw fetchError }
        guard let record = storedRecords[id] else { return nil }
        return Self.projected(record, desiredKeys: desiredKeys)
    }

    /// レコードを上書き保存します。
    ///
    /// 責務: 呼び出しと Asset の中身を記録してから、注入された失敗があれば投げ、無ければ ID をキーに保存します。
    func overwrite(_ record: CKRecord) async throws {
        overwriteCount += 1
        if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL {
            overwrittenAssetURLs.append(url)
            overwrittenAssetBytes.append(try Data(contentsOf: url))
        }
        if let overwriteError { throw overwriteError }
        storedRecords[record.recordID] = record
    }

    /// タイプとフィールド値で絞ったレコードを返します。
    ///
    /// 責務: 履歴を残し、タイプとフィールドの値が一致するレコードだけを、`desiredKeys` で射影して返します。
    func records(
        ofType recordType: String,
        whereField field: CKRecord.FieldKey,
        equals value: String,
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord] {
        queries.append((recordType, field, value))
        queryDesiredKeysHistory.append(desiredKeys)
        if let queryError { throw queryError }
        return storedRecords.values
            .filter { $0.recordType == recordType && ($0[field] as? String) == value }
            .map { Self.projected($0, desiredKeys: desiredKeys) }
    }

    /// レコードがあれば削除します。
    ///
    /// 責務: 履歴を残し、注入された失敗があれば投げ、無ければ ID のレコードを取り除きます(無くても成功)。
    func deleteRecordIfPresent(_ id: CKRecord.ID) async throws {
        deleteRequests.append(id)
        if let deleteError { throw deleteError }
        storedRecords.removeValue(forKey: id)
    }

    /// 指定したフィールドだけを持つレコードの写しを作ります。
    ///
    /// 責務: `desiredKeys` が `nil` なら元のレコードを、指定があれば指定外(特に Asset)を落とした写しを返します。
    private static func projected(_ record: CKRecord, desiredKeys: [CKRecord.FieldKey]?) -> CKRecord {
        guard let desiredKeys else { return record }
        let copy = CKRecord(recordType: record.recordType, recordID: record.recordID)
        for key in desiredKeys {
            copy[key] = record[key]
        }
        return copy
    }
}
