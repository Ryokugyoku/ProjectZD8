import Foundation
import XCTest
@testable import ProjectZD8

/// `UnavailableLocationUpdateSource` が事象を流さずに終わる流れを返すことを検証します。
@MainActor
final class UnavailableLocationUpdateSourceTests: XCTestCase {
    /// 流れを期限つきで読み切ります。
    ///
    /// 責務: 流れが2秒以内に終わったかと、流れた事象を返します。終わらなければ終了していないと報告します。
    private func drain(_ stream: AsyncStream<LocationUpdateEvent>) async -> (events: [LocationUpdateEvent], finished: Bool) {
        await withTaskGroup(of: (events: [LocationUpdateEvent], finished: Bool).self) { group in
            group.addTask {
                var events: [LocationUpdateEvent] = []
                for await event in stream { events.append(event) }
                return (events, true)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return ([], false)
            }
            let first = await group.next() ?? ([], false)
            group.cancelAll()
            return first
        }
    }

    /// 流れは事象を1つも流さずに終わります。
    ///
    /// 責務: `makeUpdates()` の流れが期限内に空のまま終了することを確認します。
    func testUpdatesFinishWithoutEmittingEvents() async {
        let result = await drain(UnavailableLocationUpdateSource().makeUpdates())

        XCTAssertTrue(result.finished, "流れが2秒以内に終わらなかった")
        XCTAssertTrue(result.events.isEmpty)
    }

    /// 何度作っても、毎回すぐ終わる流れです。
    ///
    /// 責務: 2回目の流れも空のまま終わることを確認します。
    func testEachCallReturnsAFinishingStream() async {
        let source = UnavailableLocationUpdateSource()
        for _ in 0..<2 {
            let result = await drain(source.makeUpdates())
            XCTAssertTrue(result.finished, "流れが2秒以内に終わらなかった")
            XCTAssertTrue(result.events.isEmpty)
        }
    }
}
