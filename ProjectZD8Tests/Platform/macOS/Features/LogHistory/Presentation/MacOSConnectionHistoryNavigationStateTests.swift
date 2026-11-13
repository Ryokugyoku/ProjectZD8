#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS接続履歴の一時的な階層遷移を検証します。
final class MacOSConnectionHistoryNavigationStateTests: XCTestCase {
    /// 詳細表示中のセッションが削除されたとき車両セッション一覧へ戻ることを検証します。
    ///
    /// 責務: 削除済みセッション詳細の遷移だけが経路から取り除かれることを確認します。
    func testDeletedPresentedSessionReturnsToVehicleSessionList() {
        let deletedSessionID = ConnectionSessionID()
        var subject = MacOSConnectionHistoryNavigationState()
        subject.path = [
            .vehicleSessions(.unassigned),
            .sessionDetail(deletedSessionID)
        ]

        subject.returnFromDeletedSession(availableSessionIDs: [])

        XCTAssertEqual(subject.path, [.vehicleSessions(.unassigned)])
    }

    /// 詳細表示中のセッションが残っているとき現在画面を維持することを検証します。
    ///
    /// 責務: 利用可能なセッション詳細の遷移経路が変更されないことを確認します。
    func testAvailablePresentedSessionKeepsDetailRoute() {
        let availableSessionID = ConnectionSessionID()
        var subject = MacOSConnectionHistoryNavigationState()
        subject.path = [
            .vehicleSessions(.unassigned),
            .sessionDetail(availableSessionID)
        ]

        subject.returnFromDeletedSession(availableSessionIDs: [availableSessionID])

        XCTAssertEqual(
            subject.path,
            [.vehicleSessions(.unassigned), .sessionDetail(availableSessionID)]
        )
    }

    /// 車両セッション一覧の表示中は別セッションの削除で戻らないことを検証します。
    ///
    /// 責務: セッション詳細以外の現在遷移を履歴更新後も維持することを確認します。
    func testVehicleSessionListDoesNotReturnToArchiveAfterDeletion() {
        var subject = MacOSConnectionHistoryNavigationState()
        subject.path = [.vehicleSessions(.unassigned)]

        subject.returnFromDeletedSession(availableSessionIDs: [])

        XCTAssertEqual(subject.path, [.vehicleSessions(.unassigned)])
    }
}
#endif
