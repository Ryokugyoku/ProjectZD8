import Foundation
import XCTest
@testable import ProjectZD8

/// CloudKit保存済みRawログの3日保持判断を検証します。
final class ConnectionSessionRawCacheRetentionPolicyTests: XCTestCase {
    /// 最終閲覧から3日未満のRawログは端末へ保持します。
    ///
    /// 責務: 保持期限前のローカルRawが退避対象にならないことを確認します。
    func testKeepsRawBeforeThreeDaysFromLastAccess() {
        let session = makeSession(lastAccessedAt: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(
            ConnectionSessionRawCacheRetentionPolicy().shouldEvict(
                session,
                at: Date(timeIntervalSince1970: 100 + 3 * 24 * 60 * 60 - 1)
            )
        )
    }

    /// 最終閲覧から3日経過したRawログは端末退避対象にします。
    ///
    /// 責務: 保持期限へ到達したCloudKit保存済みRawを退避対象にすることを確認します。
    func testEvictsRawAtThreeDaysFromLastAccess() {
        let session = makeSession(lastAccessedAt: Date(timeIntervalSince1970: 100))

        XCTAssertTrue(
            ConnectionSessionRawCacheRetentionPolicy().shouldEvict(
                session,
                at: Date(timeIntervalSince1970: 100 + 3 * 24 * 60 * 60)
            )
        )
    }

    /// CloudKit保存が未確認のRawログは期限を過ぎても保持します。
    ///
    /// 責務: 唯一のRawコピーを自動退避で失わないことを確認します。
    func testKeepsRawWithoutVerifiedCloudManifest() {
        var session = makeSession(lastAccessedAt: Date(timeIntervalSince1970: 100))
        session.rawLogSummary.cloudState = .failed

        XCTAssertFalse(
            ConnectionSessionRawCacheRetentionPolicy().shouldEvict(
                session,
                at: Date(timeIntervalSince1970: 1_000_000)
            )
        )
    }

    /// 指定最終閲覧日時を持つCloudKit保存済みセッションを生成します。
    ///
    /// 責務: 保持判断テストへ同一の終了済みRaw保有状態を供給します。
    /// - Parameter lastAccessedAt: 現在端末でRawを最後に閲覧した日時。
    /// - Returns: CloudKit保存済みRawを持つ終了セッション。
    private func makeSession(lastAccessedAt: Date?) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 50))
        session.endedAt = Date(timeIntervalSince1970: 60)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 2,
            localState: .available,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil,
            lastAccessedAt: lastAccessedAt
        )
        return session
    }
}
