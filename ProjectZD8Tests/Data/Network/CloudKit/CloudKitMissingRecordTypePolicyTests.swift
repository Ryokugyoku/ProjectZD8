import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `CloudKitMissingRecordTypePolicy` が「レコードタイプが無い」エラーだけを判定することを検証します。
///
/// 仕様: true になるのは CKError(または CKErrorDomain の NSError)で code が `.unknownItem` の時だけ。
final class CloudKitMissingRecordTypePolicyTests: XCTestCase {
    /// 検証対象の判定器です。
    private let policy = CloudKitMissingRecordTypePolicy()

    /// `.unknownItem` の CKError が true になることを検証します。
    ///
    /// 責務: 唯一の true のケースを確認します。
    func testUnknownItemCKErrorIsMissingRecordType() {
        XCTAssertTrue(policy.isMissingRecordType(CKError(.unknownItem)))
    }

    /// それ以外の CKError がすべて false になることを検証します。
    ///
    /// 責務: 通信・認証・混雑・部分失敗などの代表コードが誤って true にならないことを確認します。
    func testOtherCKErrorCodesAreNotMissingRecordType() {
        let codes: [CKError.Code] = [
            .networkFailure, .networkUnavailable, .notAuthenticated, .serviceUnavailable,
            .requestRateLimited, .permissionFailure, .partialFailure, .serverRecordChanged, .zoneNotFound
        ]
        for code in codes {
            XCTAssertFalse(policy.isMissingRecordType(CKError(code)), "\(code)")
        }
    }

    /// CKError 以外のエラーが false になることを検証します。
    ///
    /// 責務: 他の型のエラーを「タイプ無し」と誤判定しないことを確認します。
    func testNonCKErrorsAreNotMissingRecordType() {
        let errors: [any Error] = [
            CocoaError(.fileNoSuchFile), URLError(.notConnectedToInternet),
            ConnectionSessionRepositoryError.unavailable, CancellationError()
        ]
        for error in errors {
            XCTAssertFalse(policy.isMissingRecordType(error), "\(error)")
        }
    }

    /// CKErrorDomain の NSError で code が unknownItem のものが true になることを検証します。
    ///
    /// 責務: NSError 経由で届く CloudKit エラーを判定できることを確認します。
    func testNSErrorInCKErrorDomainWithUnknownItemIsMissingRecordType() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.unknownItem.rawValue)
        XCTAssertTrue(policy.isMissingRecordType(error))
    }

    /// CKErrorDomain の NSError で別の code のものが false になることを検証します。
    ///
    /// 責務: NSError 経由でも code を見ていることを確認します。
    func testNSErrorInCKErrorDomainWithOtherCodeIsNotMissingRecordType() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.networkFailure.rawValue)
        XCTAssertFalse(policy.isMissingRecordType(error))
    }

    /// 同じ code でもドメインが CKErrorDomain でなければ false になることを検証します。
    ///
    /// 責務: ドメインの確認を確認します。
    func testNSErrorInOtherDomainWithSameCodeIsNotMissingRecordType() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CKError.Code.unknownItem.rawValue)
        XCTAssertFalse(policy.isMissingRecordType(error))
    }
}
