#if os(iOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// iOS の車両別一覧の、手動アップロード欄の表示の種類の判定を検証します。
@MainActor
final class IOSConnectionHistoryUploadActionStyleTests: XCTestCase {
    /// 送信中のセッションは、転送の失敗より優先して進捗を出します。
    ///
    /// 責務: 送信中の ID が一致する時、転送の状態によらず `inProgress` になることを確認します。
    func testUploadingSessionIsInProgressRegardlessOfCloudState() {
        for cloudState in [ConnectionSessionCloudSyncState.failed, .notUploaded, .uploaded] {
            let session = session(cloudState: cloudState)

            XCTAssertEqual(IOSConnectionHistoryUploadActionStyle.style(for: session, uploadingSessionID: session.id), .inProgress)
        }
    }

    /// 送信中でなく前回の転送に失敗していれば、再試行を出します。
    ///
    /// 責務: 送信中が無い時と別のセッションが送信中の時の両方で `retry` になることを確認します。
    func testFailedSessionNotUploadingIsRetry() {
        let session = session(cloudState: .failed)

        XCTAssertEqual(IOSConnectionHistoryUploadActionStyle.style(for: session, uploadingSessionID: nil), .retry)
        XCTAssertEqual(IOSConnectionHistoryUploadActionStyle.style(for: session, uploadingSessionID: ConnectionSessionID()), .retry)
    }

    /// 送信中でなく失敗もしていなければ、通常のアップロードを出します。
    ///
    /// 責務: 失敗以外の転送の状態3種で `upload` になることを確認します。
    func testOtherSessionsAreUpload() {
        for cloudState in [ConnectionSessionCloudSyncState.notUploaded, .pending, .uploaded] {
            XCTAssertEqual(
                IOSConnectionHistoryUploadActionStyle.style(for: session(cloudState: cloudState), uploadingSessionID: ConnectionSessionID()),
                .upload,
                "\(cloudState)"
            )
        }
    }

    /// 転送の状態を指定してセッションを作ります。
    ///
    /// 責務: Raw の要約の転送の状態だけを変えたセッションを返します。
    /// - Parameter cloudState: iCloud への転送の状態。
    /// - Returns: セッション。
    private func session(cloudState: ConnectionSessionCloudSyncState) -> ConnectionSession {
        var session = ConnectionSession(accountIdentifier: "account")
        session.rawLogSummary.cloudState = cloudState
        return session
    }
}
#endif
