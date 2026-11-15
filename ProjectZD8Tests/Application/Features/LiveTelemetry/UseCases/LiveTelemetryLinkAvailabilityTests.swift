import XCTest
@testable import ProjectZD8

/// `LiveTelemetryLinkAvailability` が、最後に受けたリンク可用性の通知だけで状態を決めることを検証します。
///
/// 仕様(U2 受け入れ条件 5): 回復段階の最中に届いたリンク復帰を覚え、その後にリンク断が届いたら使えない状態へ戻します。
final class LiveTelemetryLinkAvailabilityTests: XCTestCase {
    /// すべての状態です。
    private let all: [LiveTelemetryLinkAvailability] = [.unknown, .available, .unavailable]

    /// リンク復帰はどの状態からでも使える状態、リンク断はどの状態からでも使えない状態にします。
    ///
    /// 責務: 3つの状態それぞれでリンク復帰・リンク断を反映した結果を確認します。
    func testLinkSignalsSetAvailabilityFromEveryState() {
        for availability in all {
            XCTAssertEqual(availability.updated(by: .linkRestored), .available, "\(availability)")
            XCTAssertEqual(availability.updated(by: .linkLost), .unavailable, "\(availability)")
        }
    }

    /// 前面復帰・背面移行の通知では状態を変えません。
    ///
    /// 責務: 3つの状態それぞれで、リンクに無関係な通知の反映結果が元のままであることを確認します。
    func testAppSignalsKeepAvailability() {
        for availability in all {
            XCTAssertEqual(availability.updated(by: .foregroundEntered), availability, "\(availability)")
            XCTAssertEqual(availability.updated(by: .backgroundEntered), availability, "\(availability)")
        }
    }

    /// 復帰の後に断が届けば使えず、断の後に復帰が届けば使える(最後の通知が勝つ)。
    ///
    /// 責務: 通知の並びを反映した最終状態を確認します。
    func testLastLinkSignalWins() {
        XCTAssertEqual(LiveTelemetryLinkAvailability.unknown.updated(by: .linkRestored).updated(by: .linkLost), .unavailable)
        XCTAssertEqual(LiveTelemetryLinkAvailability.unknown.updated(by: .linkLost).updated(by: .linkRestored), .available)
        XCTAssertEqual(
            LiveTelemetryLinkAvailability.unknown.updated(by: .linkRestored).updated(by: .backgroundEntered).updated(by: .foregroundEntered),
            .available
        )
    }
}
