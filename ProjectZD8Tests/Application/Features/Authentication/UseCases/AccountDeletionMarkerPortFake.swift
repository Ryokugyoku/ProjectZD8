import Foundation
@testable import ProjectZD8

/// 削除済みの印の確認・保存・解除を記録し、指定した操作を失敗させるテスト用の境界です。
@MainActor
final class AccountDeletionMarkerPortFake: AccountDeletionMarkerPort {
    /// 印があるものとして扱うアカウント識別子です。
    var deletedAccounts: Set<String> = []

    /// 印の確認で投げるエラーです。`nil` なら確認に成功します。
    var isDeletedError: Error?

    /// 印の保存で投げるエラーです。`nil` なら保存に成功します。
    var markError: Error?

    /// 印の解除で投げるエラーです。`nil` なら解除に成功します。
    var clearError: Error?

    /// 印の解除を要求された時に呼ぶ処理です。解除の失敗指定より前に呼びます。
    var onClear: ((String) -> Void)?

    /// 確認を要求されたアカウント識別子です(呼び出し順)。
    private(set) var checkedAccounts: [String] = []

    /// 印の保存を要求されたアカウント識別子です(呼び出し順)。
    private(set) var markedAccounts: [String] = []

    /// 印の解除を要求されたアカウント識別子です(呼び出し順)。
    private(set) var clearedAccounts: [String] = []

    /// 副作用の発生順を共有する記録先です。使わないテストでは `nil` です。
    private let recorder: DeleteAccountUseCaseRecorder?

    /// 共有の記録先を指定して生成します。
    ///
    /// 責務: 印の保存・解除を、他の副作用と同じ順序の履歴へ載せられるようにします。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。省略時は順序を記録しません。
    init(recorder: DeleteAccountUseCaseRecorder? = nil) {
        self.recorder = recorder
    }

    /// 印の有無を返します。
    ///
    /// 責務: 確認の要求を記録し、指定されたエラーか `deletedAccounts` の内容を返します。
    /// - Parameter accountIdentifier: 照会対象のアカウント識別子。
    /// - Returns: 印があれば `true`。
    func isAccountDeleted(_ accountIdentifier: String) async throws -> Bool {
        checkedAccounts.append(accountIdentifier)
        if let isDeletedError { throw isDeletedError }
        return deletedAccounts.contains(accountIdentifier)
    }

    /// 印の保存を記録します。
    ///
    /// 責務: 保存の要求を履歴へ追加し、失敗指定なら投げます。
    /// - Parameter accountIdentifier: 削除したアカウント識別子。
    func markDeleted(_ accountIdentifier: String) async throws {
        markedAccounts.append(accountIdentifier)
        try recorder?.record("mark-deleted:\(accountIdentifier)")
        if let markError { throw markError }
    }

    /// 印の解除を記録します。
    ///
    /// 責務: 解除の要求を履歴へ追加し、失敗指定なら投げます。
    /// - Parameter accountIdentifier: 利用を再開するアカウント識別子。
    func clearMarker(_ accountIdentifier: String) async throws {
        clearedAccounts.append(accountIdentifier)
        onClear?(accountIdentifier)
        try recorder?.record("clear-marker:\(accountIdentifier)")
        if let clearError { throw clearError }
    }
}
