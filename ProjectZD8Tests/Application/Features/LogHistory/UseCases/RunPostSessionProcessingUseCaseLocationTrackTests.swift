import Foundation
import XCTest
@testable import ProjectZD8

/// 後処理に足した軌跡アップロードのステップ(`.locationTrackUpload`)の順序・省略・失敗・持ち越し・中断を検証します。
@MainActor
final class RunPostSessionProcessingUseCaseLocationTrackTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = RunPostSessionProcessingUseCaseFixture
    /// 軌跡アップロードの失敗に使うエラーです。
    private let trackFailure = NSError(domain: "LocationTrackTestDomain", code: 33)
    /// アップロードの失敗に使うエラーです。
    private let uploadFailure = NSError(domain: "UploadTestDomain", code: 11)

    /// 自動アップロードがオンなら、実行順が upload → locationTrackUpload → eviction で、軌跡側へアカウント識別子が渡ります。
    ///
    /// 責務: 順序とアカウント識別子の受け渡しを確認します。
    func testOrderIsUploadThenLocationTrackThenEvictionWithAccountIdentifier() async {
        let fixture = Fixture()

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(
            fixture.stepCalls.first { $0.step == .locationTrackUpload },
            .init(step: .locationTrackUpload, accountIdentifier: "account-1")
        )
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [])
    }

    /// 自動アップロードがオフなら、2ステップとも呼ばず、省略を順に2件記録し、整理は実行します。
    ///
    /// 責務: 設計 R1(オフなら軌跡も送らない)を確認します。
    func testAutomaticUploadOffSkipsBothUploadStepsAndRunsEviction() async {
        let fixture = Fixture()
        fixture.automaticUploadEnabled = false

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(fixture.calledSteps, [.eviction])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started,
            .stepSkippedForAutomaticUploadOff(.upload),
            .stepSkippedForAutomaticUploadOff(.locationTrackUpload),
            .stepSucceeded(.eviction),
            .finished(.completed)
        ])
    }

    /// 軌跡アップロードだけが失敗したら、失敗したステップはそれだけで、整理は実行し、ネットワーク条件付きで再予約します。
    ///
    /// 責務: 軌跡アップロードの失敗の扱いを確認します。
    func testLocationTrackFailureIsReportedAloneAndRescheduled() async {
        let fixture = Fixture()
        fixture.locationTrackUploadError = trackFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.locationTrackUpload]))
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started,
            .stepSucceeded(.upload),
            .stepFailed(.locationTrackUpload, domain: "LocationTrackTestDomain", code: 33),
            .stepSucceeded(.eviction),
            .finished(.stepsFailed([.locationTrackUpload]))
        ])
        XCTAssertEqual(fixture.diagnostics.schedulingEvents, [.scheduled])
    }

    /// アップロードが失敗しても、軌跡アップロードは実行します。
    ///
    /// 責務: 前のステップの失敗が軌跡アップロードを止めないことを確認します。
    func testLocationTrackRunsEvenWhenUploadFails() async {
        let fixture = Fixture()
        fixture.uploadError = uploadFailure

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .stepsFailed([.upload]))
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
    }

    /// アップロードの後に記録が始まっていたら、軌跡アップロードを呼ばずに記録中で持ち越し、再予約します。
    ///
    /// 責務: 軌跡アップロードの前の記録開始を確認します。
    func testRecordingStartedBeforeLocationTrackDefers() async {
        let fixture = Fixture()
        fixture.duringUpload = { fixture.isRecordingActive = true }

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .deferredForActiveRecording)
        XCTAssertEqual(fixture.calledSteps, [.upload])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
    }

    /// 軌跡アップロードの実行中にキャンセルされたら、整理を呼ばずに期限切れで中断し、再予約します。
    ///
    /// 責務: 軌跡アップロード中のキャンセルを確認します。
    func testCancelledDuringLocationTrackInterruptsBeforeEviction() async {
        let fixture = Fixture()
        fixture.duringLocationTrackUpload = { Fixture.cancelCurrentTask() }

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
    }

    /// 軌跡アップロードが `CancellationError` を投げたら、整理を呼ばずに中断として扱い、失敗とは記録しません。
    ///
    /// 責務: `CancellationError` の扱いを軌跡アップロードで確認します。
    func testLocationTrackThrowingCancellationErrorInterrupts() async {
        let fixture = Fixture()
        fixture.locationTrackUploadError = CancellationError()

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started, .stepSucceeded(.upload), .interruptedByExpiration, .finished(.interruptedByExpiration)
        ])
    }

    /// `requiresAutomaticUpload` は upload と locationTrackUpload が true、eviction が false です。
    ///
    /// 責務: 3ケースの真偽を確認します。
    func testRequiresAutomaticUploadPerStep() {
        XCTAssertTrue(PostSessionProcessingStep.upload.requiresAutomaticUpload)
        XCTAssertTrue(PostSessionProcessingStep.locationTrackUpload.requiresAutomaticUpload)
        XCTAssertFalse(PostSessionProcessingStep.eviction.requiresAutomaticUpload)
    }

    /// `allCases` の順序が upload → locationTrackUpload → eviction です。
    ///
    /// 責務: 実行順が宣言順であることを確認します。
    func testAllCasesOrder() {
        XCTAssertEqual(PostSessionProcessingStep.allCases, [.upload, .locationTrackUpload, .eviction])
    }
}
