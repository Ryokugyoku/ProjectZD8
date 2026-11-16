import XCTest
@testable import ProjectZD8

/// 通知の提示の世代が、監視通知(検知・開始)と「記録を開始できませんでした」で独立し、取り下げで進むのは監視通知だけであることを検証します。
///
/// 仕様: U8 R2(失敗通知は同時に有効な検知通知を取り下げない。非同期の提示が後の提示・取り下げを追い越さない)。
final class VehicleDetectionNotificationRequestGenerationsTests: XCTestCase {
    /// 検知通知の識別子です。
    private let detected = VehicleDetectionNotificationCatalog.vehicleDetectedIdentifier
    /// 開始通知の識別子です。
    private let started = VehicleDetectionNotificationCatalog.recordingStartedIdentifier
    /// 失敗通知の識別子です。
    private let failed = VehicleDetectionNotificationCatalog.recordingStartFailedIdentifier

    /// 生成直後はどちらの世代も0です。
    ///
    /// 責務: `supervision` と `recordingStartFailure` の初期値を確認します。
    func testInitialGenerationsAreZero() {
        let generations = VehicleDetectionNotificationRequestGenerations()
        XCTAssertEqual(generations.supervision, 0)
        XCTAssertEqual(generations.recordingStartFailure, 0)
    }

    /// 検知・開始の提示は監視通知の世代を、失敗の提示は失敗の世代を1つずつ進め、もう一方は変えません。
    ///
    /// 責務: 検知→開始→失敗→失敗 の提示で返る世代と、両方の世代の値を確認します。
    func testAdvanceForPresentingCountsEachKindSeparately() {
        var generations = VehicleDetectionNotificationRequestGenerations()

        XCTAssertEqual(generations.advance(forPresenting: detected), 1)
        XCTAssertEqual(generations.advance(forPresenting: started), 2)
        XCTAssertEqual(generations.advance(forPresenting: failed), 1)
        XCTAssertEqual(generations.advance(forPresenting: failed), 2)

        XCTAssertEqual(generations.supervision, 2)
        XCTAssertEqual(generations.recordingStartFailure, 2)
    }

    /// 取り下げは監視通知の世代だけを進め、失敗の世代は変えません。
    ///
    /// 責務: 提示の後の `advanceForDismissal()` で、監視通知の世代だけが1つ進むことを確認します。
    func testDismissalAdvancesOnlySupervision() {
        var generations = VehicleDetectionNotificationRequestGenerations()
        _ = generations.advance(forPresenting: detected)
        _ = generations.advance(forPresenting: failed)

        generations.advanceForDismissal()

        XCTAssertEqual(generations.supervision, 2)
        XCTAssertEqual(generations.recordingStartFailure, 1)
    }

    /// 検知通知の提示の途中で失敗通知を提示しても、検知通知の提示は最新のままです(失敗通知が検知通知を捨てない)。
    ///
    /// 責務: 検知の世代を取った後に失敗を提示しても、検知の世代が `isCurrent` のままで、失敗の世代も `isCurrent` であることを確認します。
    func testFailurePresentationDoesNotStaleDetectionPresentation() {
        var generations = VehicleDetectionNotificationRequestGenerations()
        let detection = generations.advance(forPresenting: detected)

        let failure = generations.advance(forPresenting: failed)

        XCTAssertTrue(generations.isCurrent(detection, forPresenting: detected))
        XCTAssertTrue(generations.isCurrent(failure, forPresenting: failed))
    }

    /// 同じ種類の後の提示や監視通知の取り下げがあれば、先の提示は古くなります。失敗の提示は取り下げで古くなりません。
    ///
    /// 責務: 検知→開始の後の検知の世代、検知→取り下げの後の検知の世代が古く、失敗→取り下げの後の失敗の世代が最新、
    /// 失敗→失敗の後の先の失敗の世代が古いことを確認します。
    func testIsCurrentBecomesFalseOnlyAfterSameKindAdvance() {
        var generations = VehicleDetectionNotificationRequestGenerations()
        let firstDetection = generations.advance(forPresenting: detected)
        let start = generations.advance(forPresenting: started)
        XCTAssertFalse(generations.isCurrent(firstDetection, forPresenting: detected), "後の開始の提示で古くなる")
        XCTAssertTrue(generations.isCurrent(start, forPresenting: started))

        let firstFailure = generations.advance(forPresenting: failed)
        generations.advanceForDismissal()
        XCTAssertFalse(generations.isCurrent(start, forPresenting: started), "取り下げで古くなる")
        XCTAssertTrue(generations.isCurrent(firstFailure, forPresenting: failed), "取り下げでは失敗の提示は古くならない")

        let secondFailure = generations.advance(forPresenting: failed)
        XCTAssertFalse(generations.isCurrent(firstFailure, forPresenting: failed), "後の失敗の提示で古くなる")
        XCTAssertTrue(generations.isCurrent(secondFailure, forPresenting: failed))
    }

    /// 世代の比較は種類ごとの値で行い、同じ数値でも別の種類の世代とは比べません。
    ///
    /// 責務: 監視通知と失敗の世代がどちらも1の時、失敗の世代1が失敗として最新、監視通知の世代2は失敗としては最新でないことを確認します。
    func testIsCurrentComparesAgainstGenerationOfSameKind() {
        var generations = VehicleDetectionNotificationRequestGenerations()
        _ = generations.advance(forPresenting: detected)
        _ = generations.advance(forPresenting: detected)
        let failure = generations.advance(forPresenting: failed)

        XCTAssertEqual(failure, 1)
        XCTAssertTrue(generations.isCurrent(1, forPresenting: failed))
        XCTAssertFalse(generations.isCurrent(2, forPresenting: failed))
        XCTAssertTrue(generations.isCurrent(2, forPresenting: detected))
        XCTAssertFalse(generations.isCurrent(1, forPresenting: started))
    }
}
