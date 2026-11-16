import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleConfirmationWindowPolicy` の、窓の内外・回数上限・前面かどうかによる判定と窓の取り直しを、境界で検証します。
///
/// 仕様: U3 受け入れ条件 4・6(窓10分・回数上限600。前面にいる間は窓切れで休止せず窓を取り直す)。
@MainActor
final class AdapterLinkVehicleConfirmationWindowPolicyTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 検証対象の方針です。
    private let policy = AdapterLinkVehicleConfirmationWindowPolicy(timing: .standard)

    /// 窓の終了時刻の直前までは窓の内で、終了時刻ちょうど・直後は窓の外です。
    ///
    /// 責務: `isInsideWindow` の境界を確認します。
    func testIsInsideWindowBoundary() {
        let confirmation = F.confirmation(windowEndsAt: F.date(600))
        XCTAssertTrue(policy.isInsideWindow(confirmation, now: F.date(599.999)))
        XCTAssertFalse(policy.isInsideWindow(confirmation, now: F.date(600)))
        XCTAssertFalse(policy.isInsideWindow(confirmation, now: F.date(600.001)))
    }

    /// 回数上限の手前で窓の内なら、前面・背面にかかわらず続けます。
    ///
    /// 責務: 回数1・599で `.continueInWindow` になることを確認します。
    func testInsideWindowBelowLimitContinues() {
        for attempt in [1, F.maximumAttempts - 1] {
            for isForeground in [false, true] {
                let decision = policy.decision(for: F.confirmation(attemptCount: attempt), now: F.date(599.999), isForeground: isForeground)
                XCTAssertEqual(decision, .continueInWindow, "\(attempt) \(isForeground)")
            }
        }
    }

    /// 窓の外では、前面なら取り直し、背面なら休止です。
    ///
    /// 責務: 終了時刻ちょうどと直後で、前面は `.renewWindow`、背面は `.pause` になることを確認します。
    func testOutsideWindowRenewsInForegroundAndPausesInBackground() {
        for now in [F.date(600), F.date(600.001)] {
            XCTAssertEqual(policy.decision(for: F.confirmation(attemptCount: 3), now: now, isForeground: true), .renewWindow, "\(now)")
            XCTAssertEqual(policy.decision(for: F.confirmation(attemptCount: 3), now: now, isForeground: false), .pause, "\(now)")
        }
    }

    /// 回数上限に達したら、窓の内でも前面でも休止です。
    ///
    /// 責務: 回数600で、窓の内外・前面背面のすべてで `.pause` になることを確認します。
    func testAttemptLimitPausesEverywhere() {
        for now in [F.date(10), F.date(600)] {
            for isForeground in [false, true] {
                let decision = policy.decision(for: F.confirmation(attemptCount: F.maximumAttempts), now: now, isForeground: isForeground)
                XCTAssertEqual(decision, .pause, "\(now) \(isForeground)")
            }
        }
    }

    /// 窓の取り直しは、その時刻から10分の窓・回数1・低頻度確認中で、判定結果を引き継ぎます。
    ///
    /// 責務: `renewed` の各項目を確認します。
    func testRenewedStartsNewWindowFromNow() {
        let confirmation = F.confirmation(windowEndsAt: F.date(600), attemptCount: 42, phase: .paused, evidence: F.otherEvidence)
        let now = F.date(1_234)
        XCTAssertEqual(
            policy.renewed(confirmation, at: now),
            F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing, evidence: F.otherEvidence)
        )
    }
}
