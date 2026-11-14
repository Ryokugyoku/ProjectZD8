import Foundation
import XCTest
@testable import ProjectZD8

/// 接続履歴一覧の保管操作可否判定を検証します。
@MainActor
final class ConnectionHistorySessionActionPolicyTests: XCTestCase {
    /// iOS と macOS の一覧が共有する判定です。
    private let policy = ConnectionHistorySessionActionPolicy()

    /// 自動アップロード無効なら、未アップロードの終了済みセッションはアップロードできます。
    ///
    /// 責務: 未アップロード、待機、失敗の各転送状態とローカル状態で手動送信を出すことを確認します。
    func testCanUploadWhenAutomaticUploadDisabled() {
        for cloudState in [ConnectionSessionCloudSyncState.notUploaded, .pending, .failed] {
            for localState in [ConnectionSessionLocalRawState.empty, .available] {
                let session = makeSession(localState: localState, cloudState: cloudState)

                XCTAssertTrue(policy.canUpload(session, automaticUploadEnabled: false), "\(cloudState) \(localState)")
            }
        }
    }

    /// 未終了、除去済み、アップロード済みのセッションは自動アップロード設定によらずアップロードできません。
    ///
    /// 責務: 共通の前提条件それぞれが単独で手動送信を止めることを確認します。
    func testCannotUploadWhenPreconditionFails() {
        let unfinished = makeSession(ended: false)
        let removed = makeSession(localState: .removed)
        let uploaded = makeSession(cloudState: .uploaded)

        for session in [unfinished, removed, uploaded] {
            for automatic in [false, true] {
                XCTAssertFalse(policy.canUpload(session, automaticUploadEnabled: automatic))
            }
        }
    }

    /// 自動アップロード有効でも、転送失敗セッションには再試行用の手動アップロードを出します。
    ///
    /// 責務: macOS を含む両 OS で、失敗が行き止まりにならないことを確認します。
    func testCanUploadFailedSessionWhenAutomaticUploadEnabled() {
        for localState in [ConnectionSessionLocalRawState.empty, .available] {
            XCTAssertTrue(policy.canUpload(makeSession(localState: localState, cloudState: .failed), automaticUploadEnabled: true))
        }
    }

    /// 自動アップロード有効なら、失敗以外の未アップロード状態には手動アップロードを出しません。
    ///
    /// 責務: 未アップロードと待機で `false` になることを確認します。
    func testCannotUploadNonFailedSessionWhenAutomaticUploadEnabled() {
        XCTAssertFalse(policy.canUpload(makeSession(cloudState: .notUploaded), automaticUploadEnabled: true))
        XCTAssertFalse(policy.canUpload(makeSession(cloudState: .pending), automaticUploadEnabled: true))
    }

    /// 状態側の `isManualUploadAvailable` は同じ判定へ委譲します。
    ///
    /// 責務: 自動アップロード設定と転送状態の全組み合わせで状態側と判定が一致することを確認します。
    func testStateManualUploadAvailabilityMatchesPolicy() {
        for automatic in [false, true] {
            var state = ConnectionHistoryState()
            state.automaticUploadEnabled = automatic
            for cloudState in [ConnectionSessionCloudSyncState.notUploaded, .pending, .uploaded, .failed] {
                let session = makeSession(cloudState: cloudState)

                XCTAssertEqual(
                    state.isManualUploadAvailable(for: session),
                    policy.canUpload(session, automaticUploadEnabled: automatic)
                )
            }
        }
    }

    /// 全条件を満たすセッションは容量解放できます。
    ///
    /// 責務: 終了済み、保存済み、1件以上、アップロード済み、Manifestありで `true` になることを確認します。
    func testCanReleaseRawCacheWhenAllConditionsHold() {
        XCTAssertTrue(policy.canReleaseRawCache(makeReleasableSession()))
    }

    /// 容量解放条件のいずれかを欠くセッションは解放できません。
    ///
    /// 責務: 各条件を1つずつ崩した場合と件数0の境界で `false` になることを確認します。
    func testCannotReleaseRawCacheWhenAnyConditionFails() {
        var unfinished = makeReleasableSession()
        unfinished.endedAt = nil
        var notAvailable = makeReleasableSession()
        notAvailable.rawLogSummary.localState = .removed
        var emptyLocal = makeReleasableSession()
        emptyLocal.rawLogSummary.localState = .empty
        var zeroRecords = makeReleasableSession()
        zeroRecords.rawLogSummary.recordCount = 0
        var notUploaded = makeReleasableSession()
        notUploaded.rawLogSummary.cloudState = .failed
        var missingDigest = makeReleasableSession()
        missingDigest.rawLogSummary.manifestDigest = nil
        var emptyDigest = makeReleasableSession()
        emptyDigest.rawLogSummary.manifestDigest = ""

        for session in [unfinished, notAvailable, emptyLocal, zeroRecords, notUploaded, missingDigest, emptyDigest] {
            XCTAssertFalse(policy.canReleaseRawCache(session))
        }
    }

    /// 検証用の接続セッションを生成します。
    ///
    /// 責務: 終了有無とRaw保管状態だけを変えたセッションを返します。
    /// - Parameters:
    ///   - ended: 終了日時を設定するか。
    ///   - localState: 現在端末のRaw保管状態。
    ///   - cloudState: CloudKit転送状態。
    /// - Returns: 検証用の接続セッション。
    private func makeSession(
        ended: Bool = true,
        localState: ConnectionSessionLocalRawState = .available,
        cloudState: ConnectionSessionCloudSyncState = .notUploaded
    ) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 0))
        if ended {
            session.endedAt = Date(timeIntervalSince1970: 60)
            session.endReason = .userDisconnected
        }
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 10,
            byteCount: 1_024,
            localState: localState,
            cloudState: cloudState,
            manifestDigest: nil,
            macImportReceipt: nil
        )
        return session
    }

    /// 容量解放条件を全て満たす接続セッションを生成します。
    ///
    /// 責務: 容量解放判定の基準となるセッションを返します。
    /// - Returns: iCloud保管済みのローカルRawを持つ終了済みセッション。
    private func makeReleasableSession() -> ConnectionSession {
        var session = makeSession(localState: .available, cloudState: .uploaded)
        session.rawLogSummary.recordCount = 1
        session.rawLogSummary.manifestDigest = "digest"
        return session
    }
}
