import CloudKit
import Foundation

/// クエリの失敗が「レコードタイプがまだ存在しない」ことを表すかを判定します。
///
/// 存在しないタイプのレコードは1件も存在し得ないので、この失敗は空の結果として扱えます。
/// 返るコードが `unknownItem` であることは、実機と CloudKit の環境での確認が必要です。
nonisolated struct CloudKitMissingRecordTypePolicy: Sendable {
    /// 既定の構成で作ります。
    ///
    /// 責務: 状態を持たない判定を用意します。
    init() {}

    /// エラーがレコードタイプの不在を表すかを返します。
    ///
    /// 責務: `CKError` で code が `.unknownItem` の時だけ true にします。`.partialFailure` は中身を見ずに false です。
    /// - Parameter error: クエリが投げたエラー。
    /// - Returns: レコードタイプの不在なら true。
    func isMissingRecordType(_ error: any Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }
}
