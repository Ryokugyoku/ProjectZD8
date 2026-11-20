import XCTest
@testable import ProjectZD8

/// セッション外の後処理の診断文言が、実機テスト手順書が参照する固定文字列と完全一致することを検証します。
@MainActor
final class PostSessionProcessingDiagnosticsMessageFormatterTests: XCTestCase {
    /// テスト対象の整形器です。
    private let formatter = PostSessionProcessingDiagnosticsMessageFormatter()

    /// 予約・開始・持ち越し・省略・中断の固定文言を確認します。
    ///
    /// 責務: 引数を取らない各メソッドの文字列を確認します。
    func testFixedMessages() {
        XCTAssertEqual(formatter.scheduled(), "Post-session processing scheduled")
        XCTAssertEqual(formatter.started(), "Post-session processing started")
        XCTAssertEqual(formatter.deferredForActiveRecording(), "Post-session processing deferred: recording active")
        XCTAssertEqual(formatter.deferredForUnavailableAccount(), "Post-session processing deferred: account unavailable")
        XCTAssertEqual(formatter.interruptedByExpiration(), "Post-session processing interrupted: expired")
    }

    /// 設定オフによる省略の文言に、省いたステップ名が入ることを確認します。
    ///
    /// 責務: 自動アップロードが要る2ステップの名前が文言へ入ることを確認します。
    func testStepSkippedForAutomaticUploadOffIncludesStepName() {
        XCTAssertEqual(
            formatter.stepSkippedForAutomaticUploadOff(.upload),
            "Post-session processing step upload skipped: automatic upload off"
        )
        XCTAssertEqual(
            formatter.stepSkippedForAutomaticUploadOff(.locationTrackUpload),
            "Post-session processing step location-track-upload skipped: automatic upload off"
        )
    }

    /// 予約失敗の文言に domain と code がそのまま入ることを確認します。
    ///
    /// 責務: 仕様の例と、負の code を含む別の値で確認します。
    func testScheduleFailedIncludesDomainAndCode() {
        XCTAssertEqual(
            formatter.scheduleFailed(errorDomain: "BGTaskSchedulerErrorDomain", errorCode: 1),
            "Post-session processing schedule failed: BGTaskSchedulerErrorDomain 1"
        )
        XCTAssertEqual(
            formatter.scheduleFailed(errorDomain: "NSCocoaErrorDomain", errorCode: -4),
            "Post-session processing schedule failed: NSCocoaErrorDomain -4"
        )
    }

    /// ステップ成功の文言を全ステップで確認します。
    ///
    /// 責務: `upload`・`locationTrackUpload`・`eviction` の名前が文言へ入ることを確認します。
    func testStepSucceededForEveryStep() {
        XCTAssertEqual(formatter.stepSucceeded(.upload), "Post-session processing step upload succeeded")
        XCTAssertEqual(
            formatter.stepSucceeded(.locationTrackUpload),
            "Post-session processing step location-track-upload succeeded"
        )
        XCTAssertEqual(formatter.stepSucceeded(.eviction), "Post-session processing step eviction succeeded")
    }

    /// ステップ失敗の文言を全ステップで、domain と code つきで確認します。
    ///
    /// 責務: ステップ名とエラー分類が文言へ入ることを確認します。
    func testStepFailedForEveryStep() {
        XCTAssertEqual(
            formatter.stepFailed(.upload, errorDomain: "CKErrorDomain", errorCode: 3),
            "Post-session processing step upload failed: CKErrorDomain 3"
        )
        XCTAssertEqual(
            formatter.stepFailed(.locationTrackUpload, errorDomain: "CKErrorDomain", errorCode: 7),
            "Post-session processing step location-track-upload failed: CKErrorDomain 7"
        )
        XCTAssertEqual(
            formatter.stepFailed(.eviction, errorDomain: "GRDB.DatabaseError", errorCode: 8),
            "Post-session processing step eviction failed: GRDB.DatabaseError 8"
        )
    }

    /// 終了の文言が、completed のときだけ completed、それ以外のすべての結果で incomplete になることを確認します。
    ///
    /// 責務: 全結果(失敗ステップの組合せを含む)を網羅します。
    func testFinishedIsCompletedOnlyForCompletedOutcome() {
        XCTAssertEqual(formatter.finished(.completed), "Post-session processing finished: completed")
        let incompleteOutcomes: [PostSessionProcessingOutcome] = [
            .deferredForActiveRecording,
            .deferredForUnavailableAccount,
            .interruptedByExpiration,
            .stepsFailed([.upload]),
            .stepsFailed([.eviction]),
            .stepsFailed([.locationTrackUpload]),
            .stepsFailed([.upload, .locationTrackUpload, .eviction]),
            .stepsFailed([])
        ]
        for outcome in incompleteOutcomes {
            XCTAssertEqual(formatter.finished(outcome), "Post-session processing finished: incomplete", "\(outcome)")
        }
    }
}
