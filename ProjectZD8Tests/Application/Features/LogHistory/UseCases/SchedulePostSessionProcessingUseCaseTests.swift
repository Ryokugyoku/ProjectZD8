import Foundation
import XCTest
@testable import ProjectZD8

/// セッション外の後処理の予約が、自動アップロード設定をネットワーク条件へ写し、成否を返して記録することを検証します。
@MainActor
final class SchedulePostSessionProcessingUseCaseTests: XCTestCase {
    /// 自動アップロードがオンなら、ネットワーク条件付きで1回だけ予約し、成功を返して「予約した」を記録します。
    ///
    /// 責務: オンの予約条件と成功時の結果・記録を確認します。
    func testAutomaticUploadOnSchedulesWithNetworkOnce() {
        let scheduler = PostSessionProcessingSchedulerSpy()
        let diagnostics = PostSessionProcessingDiagnosticsSpy()
        let useCase = SchedulePostSessionProcessingUseCase(scheduler: scheduler, diagnostics: diagnostics)

        let succeeded = useCase.execute(automaticUploadEnabled: true)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(diagnostics.events, [.scheduled])
    }

    /// 自動アップロードがオフなら、ネットワーク条件なしで1回だけ予約します。
    ///
    /// 責務: オフの予約条件を確認します。
    func testAutomaticUploadOffSchedulesWithoutNetworkOnce() {
        let scheduler = PostSessionProcessingSchedulerSpy()
        let diagnostics = PostSessionProcessingDiagnosticsSpy()
        let useCase = SchedulePostSessionProcessingUseCase(scheduler: scheduler, diagnostics: diagnostics)

        let succeeded = useCase.execute(automaticUploadEnabled: false)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(scheduler.requiresNetworkConnectivityRequests, [false])
        XCTAssertEqual(diagnostics.events, [.scheduled])
    }

    /// 予約の境界が throw したら失敗を返し、「予約に失敗した」を domain と code つきで記録し、「予約した」は記録しません。
    ///
    /// 責務: 予約失敗を成功に潰さないことを確認します。
    func testSchedulerFailureReturnsFailureAndRecordsDomainAndCode() {
        let scheduler = PostSessionProcessingSchedulerSpy()
        scheduler.error = NSError(domain: "BGTaskSchedulerErrorDomain", code: 1)
        let diagnostics = PostSessionProcessingDiagnosticsSpy()
        let useCase = SchedulePostSessionProcessingUseCase(scheduler: scheduler, diagnostics: diagnostics)

        let succeeded = useCase.execute(automaticUploadEnabled: true)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(scheduler.requiresNetworkConnectivityRequests, [true])
        XCTAssertEqual(diagnostics.events, [.scheduleFailed(domain: "BGTaskSchedulerErrorDomain", code: 1)])
    }
}
