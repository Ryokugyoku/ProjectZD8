import Foundation
import XCTest
@testable import ProjectZD8

/// Garage用の車両別アクティビティ集約を検証します。
@MainActor
final class LoadVehicleActivitySummariesUseCaseTests: XCTestCase {
    /// 複数車両と未関連履歴を1回の走査で正しく分離します。
    ///
    /// 責務: 車両別の件数、最終日時、記録時間、中断、接続中状態が混線しないことを確認します。
    func testExecuteAggregatesSessionsByRegisteredVehicle() throws {
        let firstVehicleID = VehicleID()
        let secondVehicleID = VehicleID()
        var completed = session(vehicleID: firstVehicleID, startedAt: 100)
        completed.endedAt = Date(timeIntervalSince1970: 160)
        completed.endReason = .userDisconnected
        var interrupted = session(vehicleID: firstVehicleID, startedAt: 200)
        interrupted.endedAt = Date(timeIntervalSince1970: 260)
        interrupted.endReason = .connectionLost
        let connected = session(vehicleID: secondVehicleID, startedAt: 300)
        let unassigned = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 400))
        let repository = ConnectionSessionRepositoryFake(sessions: [unassigned, connected, interrupted, completed])

        let result = try LoadVehicleActivitySummariesUseCase(repository: repository)
            .execute(accountIdentifier: "account")

        XCTAssertEqual(repository.requestedAccountIdentifiers, ["account"])
        XCTAssertEqual(result[firstVehicleID]?.sessionCount, 2)
        XCTAssertEqual(result[firstVehicleID]?.lastLoggedAt, Date(timeIntervalSince1970: 260))
        XCTAssertEqual(result[firstVehicleID]?.totalRecordedDuration, 120)
        XCTAssertEqual(result[firstVehicleID]?.interruptedCount, 1)
        XCTAssertEqual(result[firstVehicleID]?.isConnected, false)
        XCTAssertEqual(result[secondVehicleID]?.sessionCount, 1)
        XCTAssertEqual(result[secondVehicleID]?.isConnected, true)
        XCTAssertEqual(result.count, 2)
    }

    /// 最新セッションのZD8専用走行距離をGarage集計へ公開します。
    ///
    /// 責務: 古い標準値ではなく新しい車種専用累積走行距離と型式がGarage表示へ渡ることを確認します。
    func testExecuteUsesLatestZD8OdometerForGarage() throws {
        let vehicleID = VehicleID()
        var older = session(vehicleID: vehicleID, startedAt: 100)
        older.endingOdometerKilometers = 30_000
        var latest = session(vehicleID: vehicleID, startedAt: 200)
        latest.endingOdometerKilometers = 30_123.4
        latest.distanceSourceModelCode = "ZD8"
        let repository = ConnectionSessionRepositoryFake(sessions: [older, latest])

        let summary = try XCTUnwrap(
            LoadVehicleActivitySummariesUseCase(repository: repository)
                .execute(accountIdentifier: "account")[vehicleID]
        )

        XCTAssertEqual(summary.latestOdometerKilometers, 30_123.4)
        XCTAssertEqual(summary.odometerModelCode, "ZD8")
    }

    /// 指定車両へ関連付いたテスト用セッションを生成します。
    ///
    /// 責務: 1件の車両IDと開始時刻を履歴集約テスト用の未終了セッションへ変換します。
    /// - Parameters:
    ///   - vehicleID: 履歴へ関連付ける登録車両ID。
    ///   - startedAt: Unix epoch秒による開始日時。
    /// - Returns: 指定車両へ関連付いた未終了セッション。
    private func session(vehicleID: VehicleID, startedAt: TimeInterval) -> ConnectionSession {
        ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: startedAt),
            vehicle: ConnectionSessionVehicle(
                id: vehicleID,
                name: "Vehicle",
                displayIdentifier: "TEST"
            )
        )
    }
}

/// 接続履歴集約テストへ固定セッション一覧を提供します。
private final class ConnectionSessionRepositoryFake: ConnectionSessionRepository {
    /// 取得要求へ返す接続セッションです。
    let storedSessions: [ConnectionSession]
    /// 取得要求で受け取ったアカウント識別子です。
    private(set) var requestedAccountIdentifiers: [String] = []

    /// 固定セッション一覧を保持するRepositoryを生成します。
    ///
    /// 責務: テスト用セッション一覧をアカウント照会可能なRepositoryへ固定します。
    /// - Parameter sessions: 取得要求へ返すセッション一覧。
    init(sessions: [ConnectionSession]) {
        storedSessions = sessions
    }

    /// テストでは保存要求を副作用なしで受理します。
    ///
    /// 責務: 集約テストで使用しない保存操作を無変更で完了します。
    /// - Parameter session: 保存対象として受け取る接続セッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッション一覧を返します。
    ///
    /// 責務: 1件のアカウント照会を記録して固定履歴を返します。
    /// - Parameter accountIdentifier: 取得対象として受け取るアカウント識別子。
    /// - Returns: 初期化時に固定した接続セッション一覧。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        requestedAccountIdentifiers.append(accountIdentifier)
        return storedSessions
    }
}
