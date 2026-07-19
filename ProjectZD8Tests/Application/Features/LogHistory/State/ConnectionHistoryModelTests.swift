import Foundation
import XCTest
@testable import ProjectZD8

/// アカウント単位の接続履歴表示状態を検証します。
@MainActor
final class ConnectionHistoryModelTests: XCTestCase {
    /// 有効化したアカウントの履歴だけを新しい順で公開します。
    ///
    /// 責務: 1件のアカウント変更が対応する履歴一覧へ変換されることを確認します。
    func testAccountActivationLoadsScopedSessions() {
        let older = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 10))
        let newer = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 20))
        let repository = FixedConnectionSessionRepository(sessions: [newer, older])
        let model = ConnectionHistoryModel(repository: repository)

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(model.state.phase, .loaded)
        XCTAssertEqual(model.state.sessions.map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.state.activeSessions.count, 2)
    }

    /// 終了済み履歴が登録車両単位に集約され、中断件数と総時間を保持することを検証します。
    ///
    /// 責務: 複数セッションを車両ID単位の履歴集計へ変換できることを確認します。
    func testClosedSessionsAreGroupedByVehicleWithAttentionSummary() {
        let vehicleID = VehicleID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let vehicle = ConnectionSessionVehicle(id: vehicleID, name: "BRZ", displayIdentifier: "ZD8")
        let completed = makeClosedSession(startedAt: 100, duration: 600, reason: .userDisconnected, vehicle: vehicle)
        var completedWithDistance = completed
        completedWithDistance.startingOdometerKilometers = 1_000
        completedWithDistance.endingOdometerKilometers = 1_001.2
        var interrupted = makeClosedSession(startedAt: 200, duration: 120, reason: .vehicleNoResponse, vehicle: vehicle)
        interrupted.startingOdometerKilometers = 1_001.2
        interrupted.endingOdometerKilometers = 1_001.5
        let state = ConnectionHistoryState(phase: .loaded, sessions: [interrupted, completedWithDistance])

        let group = try? XCTUnwrap(state.vehicleGroups.first)

        XCTAssertEqual(state.vehicleGroups.count, 1)
        XCTAssertEqual(group?.sessionCount, 2)
        XCTAssertEqual(group?.interruptedCount, 1)
        XCTAssertEqual(group?.totalDuration, 720)
        XCTAssertEqual(group?.totalDistanceKilometers ?? -.infinity, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(state.interruptedCount, 1)
    }

    /// 走行距離を確定できないセッションを含む車両集計を非対応として保持します。
    ///
    /// 責務: 部分的なA6対応履歴を不完全な総走行距離として合算しないことを確認します。
    func testVehicleDistanceIsUnsupportedWhenAnySessionLacksOdometerBounds() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        var supported = makeClosedSession(startedAt: 100, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        supported.startingOdometerKilometers = 500
        supported.endingOdometerKilometers = 500.4
        let unsupported = makeClosedSession(startedAt: 200, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        let state = ConnectionHistoryState(phase: .loaded, sessions: [unsupported, supported])

        XCTAssertNil(state.vehicleGroups.first?.totalDistanceKilometers)
    }

    /// 日付範囲と終了理由を同時適用して該当セッションだけを残すことを検証します。
    ///
    /// 責務: 複数の絞り込み条件が論理積として適用されることを確認します。
    func testDateAndEndReasonFiltersCompose() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let normal = makeClosedSession(startedAt: 100_000, duration: 300, reason: .userDisconnected, vehicle: vehicle)
        let matching = makeClosedSession(startedAt: 200_000, duration: 900, reason: .vehicleNoResponse, vehicle: vehicle)
        let tooLate = makeClosedSession(startedAt: 400_000, duration: 600, reason: .vehicleNoResponse, vehicle: vehicle)
        var state = ConnectionHistoryState(phase: .loaded, sessions: [tooLate, matching, normal])
        state.filterStartDate = Date(timeIntervalSince1970: 150_000)
        state.filterEndDate = Date(timeIntervalSince1970: 250_000)
        state.endReasonFilter = .vehicleNoResponse

        let result = state.filteredSessions(for: .registered(vehicle.id))

        XCTAssertEqual(result.map(\.id), [matching.id])
    }

    /// 走行時間による並び順が日時順と独立して適用されることを検証します。
    ///
    /// 責務: 車両別履歴を記録時間の降順へ並べ替えられることを確認します。
    func testDurationSortOrdersLongestFirst() {
        let vehicle = ConnectionSessionVehicle(id: VehicleID(), name: "BRZ", displayIdentifier: "ZD8")
        let short = makeClosedSession(startedAt: 300, duration: 60, reason: .userDisconnected, vehicle: vehicle)
        let long = makeClosedSession(startedAt: 100, duration: 900, reason: .userDisconnected, vehicle: vehicle)
        var state = ConnectionHistoryState(phase: .loaded, sessions: [short, long])
        state.sortOrder = .longestDuration

        XCTAssertEqual(state.filteredSessions(for: .registered(vehicle.id)).map(\.id), [long.id, short.id])
    }

    /// リセット操作が日付と終了理由だけを初期化し、選択中の並び順を維持することを検証します。
    ///
    /// 責務: 1件の絞り込みリセット操作を期待する履歴状態へ反映できることを確認します。
    func testFilterResetPreservesSortOrder() {
        var state = ConnectionHistoryState()
        state.filterStartDate = Date(timeIntervalSince1970: 100)
        state.filterEndDate = Date(timeIntervalSince1970: 200)
        state.endReasonFilter = .connectionLost
        state.sortOrder = .oldest
        let model = ConnectionHistoryModel(state: state, repository: FixedConnectionSessionRepository(sessions: []))

        model.send(.filtersReset)

        XCTAssertNil(model.state.filterStartDate)
        XCTAssertNil(model.state.filterEndDate)
        XCTAssertEqual(model.state.endReasonFilter, .all)
        XCTAssertEqual(model.state.sortOrder, .oldest)
    }

    /// 指定条件を持つ終了済みセッションを生成します。
    ///
    /// 責務: テスト入力を終了日時と終了理由が確定した1件のセッションへ変換します。
    /// - Parameters:
    ///   - startedAt: Unix秒で表す開始日時。
    ///   - duration: 終了までの秒数。
    ///   - reason: 終了理由。
    ///   - vehicle: 関連付ける車両情報。
    /// - Returns: 指定条件を保持する終了済みセッション。
    private func makeClosedSession(
        startedAt: TimeInterval,
        duration: TimeInterval,
        reason: ConnectionSessionEndReason,
        vehicle: ConnectionSessionVehicle
    ) -> ConnectionSession {
        let start = Date(timeIntervalSince1970: startedAt)
        var session = ConnectionSession(accountIdentifier: "account", startedAt: start, vehicle: vehicle)
        session.endedAt = start.addingTimeInterval(duration)
        session.endReason = reason
        return session
    }
}

/// テスト用の固定接続履歴を返します。
private struct FixedConnectionSessionRepository: ConnectionSessionRepository {
    /// 取得要求へ返す固定セッション一覧です。
    let sessions: [ConnectionSession]

    /// この読込専用テスト実装では保存を行いません。
    ///
    /// 責務: 保存要求を副作用なしで受理します。
    /// - Parameter session: 使用しない接続セッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッションから指定アカウント分を返します。
    ///
    /// 責務: 固定履歴を1件のアカウント識別子で絞り込みます。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: 指定アカウントに属する固定履歴。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        sessions.filter { $0.accountIdentifier == accountIdentifier }
    }
}
