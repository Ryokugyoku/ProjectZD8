import Foundation
import XCTest
@testable import ProjectZD8

/// 履歴の絞り込みの日付の既定値(開始日時の最小・最大)を検証します。
@MainActor
final class ConnectionHistoryFilterDateFallbackTests: XCTestCase {
    /// 検証対象です。
    private let fallback = ConnectionHistoryFilterDateFallback()

    /// セッションが無ければ、開始も終了も `.distantPast` です。
    ///
    /// 責務: 空の一覧の両方の既定値を確認します。
    func testEmptySessionsGiveDistantPast() {
        XCTAssertEqual(fallback.startDate(in: []), .distantPast)
        XCTAssertEqual(fallback.endDate(in: []), .distantPast)
    }

    /// 1件なら、開始も終了もその開始日時です。
    ///
    /// 責務: 1件の時に最小と最大が同じ値になることを確認します。
    func testSingleSessionGivesItsStartForBoth() {
        let start = Date(timeIntervalSince1970: 1_000)

        let sessions = [session(startedAt: start)]

        XCTAssertEqual(fallback.startDate(in: sessions), start)
        XCTAssertEqual(fallback.endDate(in: sessions), start)
    }

    /// 複数なら、並び順によらず開始は最も早い開始日時、終了は最も遅い開始日時です。
    ///
    /// 責務: 並びの途中にある最小・最大を選び、終了日時を使わないことを確認します。
    func testMultipleSessionsGiveEarliestAndLatestStart() {
        let earliest = Date(timeIntervalSince1970: 100)
        let latest = Date(timeIntervalSince1970: 900)
        var ended = session(startedAt: latest)
        ended.endedAt = Date(timeIntervalSince1970: 5_000)

        let sessions = [session(startedAt: Date(timeIntervalSince1970: 500)), session(startedAt: earliest), ended]

        XCTAssertEqual(fallback.startDate(in: sessions), earliest)
        XCTAssertEqual(fallback.endDate(in: sessions), latest)
    }

    /// 開始日時を指定してセッションを作ります。
    ///
    /// 責務: 確かめない項目を既定値にしたセッションを返します。
    /// - Parameter startedAt: 開始日時。
    /// - Returns: セッション。
    private func session(startedAt: Date) -> ConnectionSession {
        ConnectionSession(accountIdentifier: "account", startedAt: startedAt)
    }
}
