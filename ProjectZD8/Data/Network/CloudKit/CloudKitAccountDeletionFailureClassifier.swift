import CloudKit
import Foundation

/// CloudKitのエラーを、アカウント削除画面に表示する失敗の原因へ分類します。
struct CloudKitAccountDeletionFailureClassifier: AccountDeletionFailureClassifying {
    /// 1件のエラーを失敗の原因へ分類します。
    ///
    /// 責務: `CKError` のコードを、iCloud未サインイン・通信不能・混雑の3原因へ対応付けます。
    /// 一部失敗(`partialFailure`)は含まれる個別エラーを調べ、分類できる最初の原因を採用します。それ以外は `.deletionFailed` です。
    /// - Parameter error: アカウント削除中に投げられたエラー。
    /// - Returns: 表示に使う失敗の原因。
    func failure(for error: Error) -> AccountDeletionFailure {
        guard let ckError = error as? CKError else { return .deletionFailed }
        if ckError.code == .partialFailure {
            let nested = (ckError.partialErrorsByItemID ?? [:]).values.map { failure(for: $0) }
            return nested.first { $0 != .deletionFailed } ?? .deletionFailed
        }
        return Self.failure(forCode: ckError.code)
    }

    /// CloudKitのエラーコードを原因へ対応付けます。
    ///
    /// 責務: 1件のコードを、再試行の案内が異なる原因へ分類します。
    /// - Parameter code: CloudKitのエラーコード。
    /// - Returns: 対応する原因。対応が無ければ `.deletionFailed`。
    private static func failure(forCode code: CKError.Code) -> AccountDeletionFailure {
        switch code {
        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted:
            .iCloudUnavailable
        case .networkUnavailable, .networkFailure:
            .networkUnavailable
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            .serviceBusy
        default:
            .deletionFailed
        }
    }
}
