#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOS車両接続中の画面自動ロック抑止境界を検証します。
@MainActor
final class IOSVehicleConnectionScreenSleepInhibitorTests: XCTestCase {
    /// 接続開始と終了をiOSのアイドルタイマー設定へそのまま反映します。
    ///
    /// 責務: 車両接続ライフサイクルが画面自動ロック抑止の開始と解除へ変換されることを確認します。
    func testConnectionLifecycleUpdatesIdleTimerDisabledState() {
        var states: [Bool] = []
        let inhibitor = IOSVehicleConnectionScreenSleepInhibitor {
            states.append($0)
        }

        inhibitor.setVehicleConnectionActive(true)
        inhibitor.setVehicleConnectionActive(false)

        XCTAssertEqual(states, [true, false])
    }
}
#endif
