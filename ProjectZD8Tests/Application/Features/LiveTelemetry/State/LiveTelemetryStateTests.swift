import XCTest
@testable import ProjectZD8

/// 表示状態のフェーズから接続中・受信中・切断中を判定することを検証します。
final class LiveTelemetryStateTests: XCTestCase {
    /// 一時停止は接続中だが受信中ではなく、受信中は読み込み済みだけです。
    ///
    /// 責務: 6つのフェーズの3つの判定を確認します。
    func testPhaseFlags() {
        let cases: [(LiveTelemetryState.Phase, Bool, Bool, Bool)] = [
            (.idle, false, false, false),
            (.reading, true, false, false),
            (.loaded, true, true, false),
            (.paused, true, false, false),
            (.stopping, true, false, true),
            (.failed, false, false, false)
        ]
        for (phase, active, receiving, disconnecting) in cases {
            var state = LiveTelemetryState()
            state.phase = phase

            XCTAssertEqual(state.isConnectionActive, active, "\(phase)")
            XCTAssertEqual(state.isReceiving, receiving, "\(phase)")
            XCTAssertEqual(state.isDisconnecting, disconnecting, "\(phase)")
        }
    }
}
