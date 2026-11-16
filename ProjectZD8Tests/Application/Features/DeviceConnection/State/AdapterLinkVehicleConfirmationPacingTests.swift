import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleConfirmationPacing` の、最短間隔に達するまでの残り時間と次の作用を、境界で検証します。
///
/// 仕様: U3 受け入れ条件 1・3(結果の受信を次の確認の起点にし、最短間隔より早く返った時だけ残り時間を待つ)。
final class AdapterLinkVehicleConfirmationPacingTests: XCTestCase {
    /// 最短間隔1秒の方針です。
    private let pacing = AdapterLinkVehicleConfirmationPacing(minimumInterval: 1)
    /// 確認を送った時刻です。
    private let sentAt = Date(timeIntervalSinceReferenceDate: 1_000)

    /// 送った時刻が無ければ待ちません。
    ///
    /// 責務: `sentAt` が `nil` の時に残り時間が `nil` で、次の作用が確認であることを確認します。
    func testNoSentAtMeansNoWait() {
        XCTAssertNil(pacing.remainingWait(sentAt: nil, now: sentAt))
        XCTAssertEqual(pacing.nextEffect(timeout: .adapterMaximum, sentAt: nil, now: sentAt), .confirmVehicle(.adapterMaximum))
    }

    /// 最短間隔ちょうど・直後では待たず、次の作用は確認です。
    ///
    /// 責務: 経過1秒・1.001秒で残り時間が `nil` で、指定のタイムアウトの確認になることを確認します。
    func testAtOrAfterMinimumIntervalDoesNotWait() {
        for elapsed in [1.0, 1.001, 30] {
            let now = sentAt.addingTimeInterval(elapsed)
            XCTAssertNil(pacing.remainingWait(sentAt: sentAt, now: now), "\(elapsed)")
            XCTAssertEqual(pacing.nextEffect(timeout: .heldWatch, sentAt: sentAt, now: now), .confirmVehicle(.heldWatch), "\(elapsed)")
        }
    }

    /// 最短間隔より前(即時・直前)では、残り時間だけ待ちます。
    ///
    /// 責務: 経過0秒で1秒、0.999秒で約1ミリ秒(誤差2マイクロ秒以内)の待ちになり、次の作用が待ちの予約になることを確認します。
    func testBeforeMinimumIntervalWaitsForRemainder() {
        let cases: [(TimeInterval, Duration)] = [(0, .seconds(1)), (0.5, .milliseconds(500)), (0.999, .milliseconds(1))]
        for (elapsed, expected) in cases {
            let now = sentAt.addingTimeInterval(elapsed)
            guard let wait = pacing.remainingWait(sentAt: sentAt, now: now) else {
                XCTFail("待たない: \(elapsed)")
                continue
            }
            XCTAssertLessThanOrEqual(max(wait - expected, expected - wait), .microseconds(2), "\(elapsed) \(wait)")
            XCTAssertEqual(pacing.nextEffect(timeout: .adapterMaximum, sentAt: sentAt, now: now), .scheduleVehicleConfirmation(after: wait), "\(elapsed)")
        }
    }
}
