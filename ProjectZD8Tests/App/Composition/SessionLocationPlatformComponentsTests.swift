#if os(macOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// macOS の位置記録の部品が、位置を扱わないプラットフォームとして振る舞うことを検証します。
@MainActor
final class SessionLocationPlatformComponentsTests: XCTestCase {
    /// 流れの消費結果を集める入れ物です。
    private final class Collector {
        /// 受け取った事象です。
        var events: [LocationUpdateEvent] = []
        /// 流れが終わったら `true` です。
        var isFinished = false
    }

    /// 許可の境界は未対応のプラットフォームを返します。
    ///
    /// 責務: macOS の許可の現在値が `unsupportedPlatform` であることを確認します。
    func testAuthorizationReportsUnsupportedPlatform() {
        let components = MacOSApplicationComposition.makeSessionLocationPlatformComponents()

        XCTAssertEqual(components.authorization.currentPermission, LocationPermission.unsupportedPlatform)
    }

    /// 位置の取得元は、事象を流さずに終わります。
    ///
    /// 責務: 期限つきで流れの終了を待ち、事象が1件も流れないことを確認します。
    func testSourceFinishesWithoutEvents() async {
        let components = MacOSApplicationComposition.makeSessionLocationPlatformComponents()
        let updates = components.source.makeUpdates()
        let collector = Collector()
        let task = Task { @MainActor in
            for await event in updates { collector.events.append(event) }
            collector.isFinished = true
        }
        defer { task.cancel() }

        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが終わる") { collector.isFinished }

        XCTAssertEqual(collector.events, [])
    }

    /// 前面判定は常に前面を返します。
    ///
    /// 責務: macOS では前面かどうかの判定が true になることを確認します。
    func testIsForegroundIsTrue() {
        let components = MacOSApplicationComposition.makeSessionLocationPlatformComponents()

        XCTAssertTrue(components.isForeground())
    }
}
#endif
