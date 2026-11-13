import CloudKit
import XCTest
@testable import ProjectZD8

/// CloudKitのエラーの分類を確認します。
final class CloudKitSyncErrorClassifierTests: XCTestCase {
    private let classifier = CloudKitSyncErrorClassifier()

    /// 責務: 利用者へ見せる失敗への変換を確認します。
    func testFailureMapping() {
        XCTAssertEqual(classifier.failure(for: CKError(.networkFailure)), .network)
        XCTAssertEqual(classifier.failure(for: CKError(.networkUnavailable)), .network)
        XCTAssertEqual(classifier.failure(for: CKError(.requestRateLimited)), .network)
        XCTAssertEqual(classifier.failure(for: CKError(.quotaExceeded)), .quotaExceeded)
        XCTAssertEqual(classifier.failure(for: CKError(.unknownItem)), .notFound)
        XCTAssertEqual(classifier.failure(for: CKError(.permissionFailure)), .other)
        XCTAssertEqual(classifier.failure(for: SessionArchiveCodecError.digestMismatch), .integrity)
        XCTAssertEqual(classifier.failure(for: SyncLocalStoreError.rowNotFound), .notFound)
        XCTAssertEqual(classifier.failure(for: CloudSyncFailure.quotaExceeded), .quotaExceeded)
        XCTAssertEqual(classifier.failure(for: CocoaError(.fileNoSuchFile)), .other)
    }

    /// 責務: アーカイブ削除で「既に無い」と扱うエラーを確認します。
    func testAlreadyGone() {
        XCTAssertTrue(classifier.isAlreadyGone(CKError(.unknownItem)))
        XCTAssertTrue(classifier.isAlreadyGone(CKError(.zoneNotFound)))
        XCTAssertFalse(classifier.isAlreadyGone(CKError(.networkFailure)))
        XCTAssertFalse(classifier.isAlreadyGone(CocoaError(.fileNoSuchFile)))
    }

    /// 責務: レコード保存失敗の対処の振り分けを確認します。
    func testSaveFailureHandling() {
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.serverRecordChanged)), .resolveConflict)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.zoneNotFound)), .recreateZone)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.unknownItem)), .recreateRecord)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.referenceViolation)), .retry)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.assetFileNotFound)), .retry)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.networkFailure)), .automaticRetry)
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.quotaExceeded)), .report(.quotaExceeded))
        XCTAssertEqual(classifier.handling(forSaveError: CKError(.invalidArguments)), .report(.other))
    }
}
