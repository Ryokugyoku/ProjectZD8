import Foundation
import XCTest
@testable import ProjectZD8

/// セッション外の後処理の実行条件・順序・結果・再予約・診断記録を、仕様の受け入れ条件どおりに検証します。
///
/// 期限切れ(キャンセル)の条件は `RunPostSessionProcessingUseCaseExpirationTests` で検証します。
@MainActor
final class RunPostSessionProcessingUseCaseTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = RunPostSessionProcessingUseCaseFixture
    /// アップロードの失敗に使うエラーです。
    private let uploadFailure = NSError(domain: "UploadTestDomain", code: 11)
    /// 整理の失敗に使うエラーです。
    private let evictionFailure = NSError(domain: "EvictionTestDomain", code: 22)

    /// 開始時に記録中なら、どのステップも呼ばずに記録中で持ち越し、再予約します。
    ///
    /// 責務: 仕様1(開始時の記録中)を確認します。
    func testRecordingActiveAtStartDefersWithoutCallingSteps() async {
        let fixture = Fixture()
        fixture.isRecordingActive = true

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .deferredForActiveRecording)
        XCTAssertEqual(fixture.stepCalls, [])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests.count, 1)
        XCTAssertEqual(
            fixture.diagnostics.processingEvents,
            [.started, .deferredForActiveRecording, .finished(.deferredForActiveRecording)]
        )
        XCTAssertEqual(fixture.diagnostics.schedulingEvents, [.scheduled])
    }

    /// 自動アップロードがオンなら、アップロード → 軌跡アップロード → 整理の順に同じアカウントで1回ずつ呼び、completed で再予約しません。
    ///
    /// 責務: 仕様2(オンで両ステップ成功)と、成功の診断記録を確認します。
    func testUploadThenLocationTrackUploadThenEvictionCompleteWithoutReschedule() async {
        let fixture = Fixture()

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(fixture.stepCalls, [
            .init(step: .upload, accountIdentifier: "account-1"),
            .init(step: .locationTrackUpload, accountIdentifier: "account-1"),
            .init(step: .eviction, accountIdentifier: "account-1")
        ])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [])
        XCTAssertEqual(
            fixture.diagnostics.processingEvents,
            [
                .started, .stepSucceeded(.upload), .stepSucceeded(.locationTrackUpload),
                .stepSucceeded(.eviction), .finished(.completed)
            ]
        )
        XCTAssertEqual(fixture.diagnostics.schedulingEvents, [])
    }

    /// 自動アップロードがオフなら、アップロードと軌跡アップロードを呼ばずに整理だけを呼び、整理が成功すれば completed で再予約しません。
    ///
    /// 責務: 仕様3(オフでアップロード省略)と、省略の診断記録を確認します。
    func testAutomaticUploadOffSkipsUploadAndCompletesAfterEviction() async {
        let fixture = Fixture()
        fixture.automaticUploadEnabled = false

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(fixture.stepCalls, [.init(step: .eviction, accountIdentifier: "account-1")])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [])
        XCTAssertEqual(
            fixture.diagnostics.processingEvents,
            [
                .started,
                .stepSkippedForAutomaticUploadOff(.upload),
                .stepSkippedForAutomaticUploadOff(.locationTrackUpload),
                .stepSucceeded(.eviction),
                .finished(.completed)
            ]
        )
    }

    /// アップロードが失敗しても整理を呼び、結果からアップロードの失敗が分かり、ネットワーク条件付きで再予約します。
    ///
    /// 責務: 仕様4(アップロード失敗)・仕様8(オンは true)・仕様9(失敗の domain と code)を確認します。
    func testUploadFailureStillRunsEvictionAndReschedulesWithNetwork() async {
        let fixture = Fixture()
        fixture.uploadError = uploadFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.upload]))
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started,
            .stepFailed(.upload, domain: "UploadTestDomain", code: 11),
            .stepSucceeded(.locationTrackUpload),
            .stepSucceeded(.eviction),
            .finished(.stepsFailed([.upload]))
        ])
        XCTAssertEqual(fixture.diagnostics.schedulingEvents, [.scheduled])
    }

    /// 整理が失敗しても先にアップロードは呼ばれており、結果から整理の失敗が分かり、再予約します。
    ///
    /// 責務: 仕様4(整理失敗)を確認します。
    func testEvictionFailureAfterUploadIsReportedAndRescheduled() async {
        let fixture = Fixture()
        fixture.evictionError = evictionFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.eviction]))
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started,
            .stepSucceeded(.upload),
            .stepSucceeded(.locationTrackUpload),
            .stepFailed(.eviction, domain: "EvictionTestDomain", code: 22),
            .finished(.stepsFailed([.eviction]))
        ])
    }

    /// 両方のステップが失敗したら、結果から両方の失敗が分かり、どちらも成功として記録しません。
    ///
    /// 責務: 仕様4(両方失敗)と仕様9(成功していないものを成功として記録しない)を確認します。
    func testBothStepsFailingAreReportedTogether() async {
        let fixture = Fixture()
        fixture.uploadError = uploadFailure
        fixture.evictionError = evictionFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.upload, .eviction]))
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests.count, 1)
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started,
            .stepFailed(.upload, domain: "UploadTestDomain", code: 11),
            .stepSucceeded(.locationTrackUpload),
            .stepFailed(.eviction, domain: "EvictionTestDomain", code: 22),
            .finished(.stepsFailed([.upload, .eviction]))
        ])
    }

    /// 自動アップロードがオフのアカウントで未完了なら、ネットワーク条件なしで再予約します。
    ///
    /// 責務: 仕様8(オフは false)を確認します。
    func testRescheduleWithoutNetworkWhenAutomaticUploadOff() async {
        let fixture = Fixture()
        fixture.automaticUploadEnabled = false
        fixture.evictionError = evictionFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.eviction]))
        XCTAssertEqual(fixture.calledSteps, [.eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [false])
    }

    /// アップロードの後に記録が始まっていたら、軌跡アップロードも整理も呼ばずに記録中で持ち越し、再予約します。
    ///
    /// 責務: 仕様6(ステップ間の記録開始)を確認します。
    func testRecordingStartedAfterUploadDefersRemainingSteps() async {
        let fixture = Fixture()
        fixture.duringUpload = { fixture.isRecordingActive = true }

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .deferredForActiveRecording)
        XCTAssertEqual(fixture.calledSteps, [.upload])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started, .stepSucceeded(.upload), .deferredForActiveRecording, .finished(.deferredForActiveRecording)
        ])
    }

    /// アカウントを解決できない(`nil`)なら、どのステップも呼ばずにアカウント未解決で持ち越し、ネットワーク条件なしで再予約します。
    ///
    /// 責務: 仕様7(`nil`)と仕様8(未解決は false)を確認します。
    func testUnresolvedAccountDefersWithoutNetworkReschedule() async {
        let fixture = Fixture()
        fixture.accountIdentifier = nil

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .deferredForUnavailableAccount)
        XCTAssertEqual(fixture.stepCalls, [])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [false])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started, .deferredForUnavailableAccount, .finished(.deferredForUnavailableAccount)
        ])
    }

    /// 空文字のアカウント識別子は解決できないものとして扱い、どのステップも呼ばずに持ち越します。
    ///
    /// 責務: 仕様7(空文字)を確認します。
    func testEmptyAccountIdentifierDefersAsUnavailable() async {
        let fixture = Fixture()
        fixture.accountIdentifier = ""

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .deferredForUnavailableAccount)
        XCTAssertEqual(fixture.stepCalls, [])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [false])
        XCTAssertTrue(fixture.diagnostics.processingEvents.contains(.deferredForUnavailableAccount))
    }

    /// 再予約自体が失敗しても結果は変わらず、予約の失敗が domain と code つきで記録され、予約したとは記録しません。
    ///
    /// 責務: 仕様10(再予約の失敗)を確認します。
    func testRescheduleFailureKeepsOutcomeAndRecordsScheduleFailure() async {
        let fixture = Fixture()
        fixture.uploadError = uploadFailure
        fixture.scheduler.error = NSError(domain: "BGTaskSchedulerErrorDomain", code: 1)

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.upload]))
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(
            fixture.diagnostics.schedulingEvents,
            [.scheduleFailed(domain: "BGTaskSchedulerErrorDomain", code: 1)]
        )
        XCTAssertEqual(fixture.diagnostics.processingEvents.last, .finished(.stepsFailed([.upload])))
    }
}
