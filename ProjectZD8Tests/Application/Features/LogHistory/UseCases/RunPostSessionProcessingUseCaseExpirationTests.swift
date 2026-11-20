import Foundation
import XCTest
@testable import ProjectZD8

/// セッション外の後処理が、期限切れ(実行中の `Task` のキャンセル)で残りを呼ばずに中断し、再予約することを検証します。
///
/// キャンセルはステップのフェイクの中、または実行前に、その `Task` 自身へ決定的に起こします(時間待ちはしません)。
@MainActor
final class RunPostSessionProcessingUseCaseExpirationTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = RunPostSessionProcessingUseCaseFixture

    /// 開始前にキャンセル済みなら、どのステップも呼ばずに期限切れで中断し、再予約します。
    ///
    /// 責務: 仕様5(a)を確認します。
    func testCancelledBeforeStartCallsNoStep() async {
        let fixture = Fixture()

        let outcome = await fixture.run(cancelsBeforeStart: true)

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.stepCalls, [])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests.count, 1)
        XCTAssertEqual(
            fixture.diagnostics.processingEvents,
            [.started, .interruptedByExpiration, .finished(.interruptedByExpiration)]
        )
    }

    /// アップロードの実行中にキャンセルされたら、軌跡アップロードも整理も呼ばずに期限切れで中断し、再予約します。
    ///
    /// 責務: 仕様5(b)を確認します。アップロード自体は正常に戻ります。
    func testCancelledDuringUploadSkipsRemainingSteps() async {
        let fixture = Fixture()
        fixture.duringUpload = { Fixture.cancelCurrentTask() }

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.calledSteps, [.upload])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started, .stepSucceeded(.upload), .interruptedByExpiration, .finished(.interruptedByExpiration)
        ])
    }

    /// アップロードが `CancellationError` を投げたら、軌跡アップロードも整理も呼ばずに中断として扱い、失敗とは記録しません。
    ///
    /// 責務: 仕様5(c)をアップロードで確認します。
    func testUploadThrowingCancellationErrorInterrupts() async {
        let fixture = Fixture()
        fixture.uploadError = CancellationError()

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.calledSteps, [.upload])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests.count, 1)
        XCTAssertEqual(
            fixture.diagnostics.processingEvents,
            [.started, .interruptedByExpiration, .finished(.interruptedByExpiration)]
        )
    }

    /// 整理が `CancellationError` を投げても中断として扱い、結果は completed になりません。
    ///
    /// 責務: 仕様5(c)を整理で確認します。
    func testEvictionThrowingCancellationErrorInterrupts() async {
        let fixture = Fixture()
        fixture.evictionError = CancellationError()

        let outcome = await fixture.run()

        XCTAssertEqual(outcome, .interruptedByExpiration)
        XCTAssertEqual(fixture.calledSteps, [.upload, .locationTrackUpload, .eviction])
        XCTAssertEqual(fixture.scheduler.requiresNetworkConnectivityRequests.count, 1)
        XCTAssertEqual(fixture.diagnostics.processingEvents, [
            .started, .stepSucceeded(.upload), .stepSucceeded(.locationTrackUpload),
            .interruptedByExpiration, .finished(.interruptedByExpiration)
        ])
    }
}
