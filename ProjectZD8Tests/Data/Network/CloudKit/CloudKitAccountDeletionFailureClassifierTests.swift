import CloudKit
import XCTest
@testable import ProjectZD8

/// `CloudKitAccountDeletionFailureClassifier` が、CloudKit のエラーコードを削除の失敗の原因へ分類することを検証します。
///
/// 仕様: iCloud 系3種 → `.iCloudUnavailable`、通信系2種 → `.networkUnavailable`、混雑系3種 → `.serviceBusy`。
/// `partialFailure` は内訳の分類できる最初の原因。それ以外の CKError と CKError 以外は `.deletionFailed`。
final class CloudKitAccountDeletionFailureClassifierTests: XCTestCase {
    /// 検証対象の分類器です。
    private let classifier = CloudKitAccountDeletionFailureClassifier()

    /// CKError 以外の検証用エラーです。
    private struct PlainError: Error {}

    /// コードごとの期待する原因を検証します。
    ///
    /// 責務: 仕様の対応表にある全コードが、期待する原因へ分類されることを確認します。
    func testEachMappedCodeClassifiesToItsCause() {
        let table: [(CKError.Code, AccountDeletionFailure)] = [
            (.notAuthenticated, .iCloudUnavailable),
            (.accountTemporarilyUnavailable, .iCloudUnavailable),
            (.managedAccountRestricted, .iCloudUnavailable),
            (.networkUnavailable, .networkUnavailable),
            (.networkFailure, .networkUnavailable),
            (.requestRateLimited, .serviceBusy),
            (.zoneBusy, .serviceBusy),
            (.serviceUnavailable, .serviceBusy)
        ]
        for (code, expected) in table {
            XCTAssertEqual(classifier.failure(for: CKError(code)), expected, "\(code)")
        }
    }

    /// 対応表に無い CKError は `.deletionFailed` になることを検証します。
    ///
    /// 責務: 代表的な他のコードが分類されないことを確認します。
    func testUnmappedCodesClassifyToDeletionFailed() {
        let codes: [CKError.Code] = [.internalError, .quotaExceeded, .permissionFailure, .unknownItem, .limitExceeded, .serverRejectedRequest]
        for code in codes {
            XCTAssertEqual(classifier.failure(for: CKError(code)), .deletionFailed, "\(code)")
        }
    }

    /// CKError 以外のエラーは `.deletionFailed` になることを検証します。
    ///
    /// 責務: CloudKit 由来でないエラーを分類しないことを確認します。
    func testNonCloudKitErrorClassifiesToDeletionFailed() {
        XCTAssertEqual(classifier.failure(for: PlainError()), .deletionFailed)
        XCTAssertEqual(classifier.failure(for: URLError(.notConnectedToInternet)), .deletionFailed)
    }

    /// 一部失敗は、内訳の分類できる原因を採用することを検証します。
    ///
    /// 責務: 分類できない内訳と分類できる内訳が混在しても、分類できる原因になることを確認します。
    func testPartialFailureUsesClassifiableNestedCause() {
        let nested: [AnyHashable: Error] = [
            "unknown": CKError(.unknownItem),
            "network": CKError(.networkFailure),
            "plain": PlainError()
        ]

        XCTAssertEqual(classifier.failure(for: partialFailure(nested)), .networkUnavailable)
    }

    /// 一部失敗の内訳が全て分類できなければ `.deletionFailed` になることを検証します。
    ///
    /// 責務: 内訳が全て未分類の場合と、内訳が空の場合を確認します。
    func testPartialFailureWithoutClassifiableCauseIsDeletionFailed() {
        XCTAssertEqual(classifier.failure(for: partialFailure(["unknown": CKError(.unknownItem), "plain": PlainError()])), .deletionFailed)
        XCTAssertEqual(classifier.failure(for: partialFailure([:])), .deletionFailed)
        XCTAssertEqual(classifier.failure(for: CKError(.partialFailure)), .deletionFailed)
    }

    /// 入れ子の一部失敗も内訳をたどることを検証します。
    ///
    /// 責務: 一部失敗の内訳が更に一部失敗でも、最終的な原因が採用されることを確認します。
    func testNestedPartialFailureIsResolvedRecursively() {
        let inner = partialFailure(["zone": CKError(.zoneBusy)])

        XCTAssertEqual(classifier.failure(for: partialFailure(["inner": inner])), .serviceBusy)
    }

    /// 内訳付きの一部失敗エラーを作ります。
    ///
    /// 責務: `partialErrorsByItemID` に内訳を持つ `CKError` を組み立てます。
    /// - Parameter nested: 項目ごとのエラー。
    /// - Returns: 一部失敗のエラー。
    private func partialFailure(_ nested: [AnyHashable: Error]) -> CKError {
        CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: nested])
    }
}
