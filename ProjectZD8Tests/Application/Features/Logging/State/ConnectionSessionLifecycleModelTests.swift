import Foundation
import XCTest
@testable import ProjectZD8

/// 接続セッションの開始、車両関連付け、終了を検証します。
@MainActor
final class ConnectionSessionLifecycleModelTests: XCTestCase {
    /// HOME開始から車両確定と無応答終了までを同じセッションIDへ保存します。
    ///
    /// 責務: 1回の接続ライフサイクルが安定IDを維持して終端されることを確認します。
    func testLifecycleKeepsSessionIDWhileBindingVehicleAndEnding() throws {
        let repository = RecordingConnectionSessionRepository()
        let sessionID = ConnectionSessionID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let startedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 200)
        var dates = [startedAt, endedAt].makeIterator()
        var historyChangeCount = 0
        let model = ConnectionSessionLifecycleModel(
            repository: repository,
            now: { dates.next()! },
            makeID: { sessionID },
            historyDidChange: { historyChangeCount += 1 }
        )
        let vehicle = VehicleProfile(
            id: VehicleID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
            vin: "TESTVIN",
            name: "BRZ"
        )

        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        model.send(.vehicleResolved(vehicle))
        model.send(.odometerObserved(kilometers: 12_345.6))
        model.send(.odometerObserved(kilometers: 12_346.8))
        model.send(.endRequested(.vehicleNoResponse))

        let saved = try XCTUnwrap(repository.storage[sessionID.rawValue])
        XCTAssertEqual(saved.id, sessionID)
        XCTAssertEqual(saved.vehicle?.id, vehicle.id)
        XCTAssertEqual(saved.startedAt, startedAt)
        XCTAssertEqual(saved.endedAt, endedAt)
        XCTAssertEqual(saved.endReason, .vehicleNoResponse)
        XCTAssertEqual(saved.startingOdometerKilometers, 12_345.6)
        XCTAssertEqual(saved.endingOdometerKilometers, 12_346.8)
        XCTAssertEqual(try XCTUnwrap(saved.recordedDistanceKilometers), 1.2, accuracy: 0.000_1)
        XCTAssertEqual(saved.status, .interrupted)
        XCTAssertNil(model.activeSession)
        XCTAssertEqual(historyChangeCount, 5)
    }

    /// 無効な累積走行距離をセッションへ保存しません。
    ///
    /// 責務: 非有限値と負値が走行距離差分へ混入しないことを確認します。
    func testInvalidOdometerObservationsRemainUnsupported() throws {
        let repository = RecordingConnectionSessionRepository()
        let model = ConnectionSessionLifecycleModel(repository: repository)

        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        model.send(.odometerObserved(kilometers: -.infinity))
        model.send(.odometerObserved(kilometers: -1))

        let session = try XCTUnwrap(model.activeSession)
        XCTAssertNil(session.startingOdometerKilometers)
        XCTAssertNil(session.endingOdometerKilometers)
        XCTAssertNil(session.recordedDistanceKilometers)
    }

    /// アプリ再開時に残った未終了セッションを接続中のまま復元しません。
    ///
    /// 責務: 以前の未終了セッションが異常終了へ回復されることを確認します。
    func testAccountActivationClosesPersistedUnfinishedSession() throws {
        let repository = RecordingConnectionSessionRepository()
        let session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 50))
        repository.storage[session.id.rawValue] = session
        let recoveryDate = Date(timeIntervalSince1970: 75)
        let model = ConnectionSessionLifecycleModel(repository: repository, now: { recoveryDate })

        model.send(.accountIdentifierChanged("account"))

        let recovered = try XCTUnwrap(repository.storage[session.id.rawValue])
        XCTAssertEqual(recovered.endedAt, recoveryDate)
        XCTAssertEqual(recovered.endReason, .unexpectedTermination)
        XCTAssertEqual(recovered.status, .interrupted)
    }
}

/// テスト用に接続セッションをメモリへ記録します。
private final class RecordingConnectionSessionRepository: ConnectionSessionRepository {
    /// セッションID単位の保存内容です。
    var storage: [UUID: ConnectionSession] = [:]

    /// 指定セッションをメモリへ保存します。
    ///
    /// 責務: 1件の接続セッションをテスト用辞書へ記録します。
    /// - Parameter session: 記録する接続セッション。
    func save(_ session: ConnectionSession) throws {
        storage[session.id.rawValue] = session
    }

    /// 指定アカウントのセッションを新しい順で返します。
    ///
    /// 責務: テスト用辞書から1件のアカウントに属する履歴を抽出します。
    /// - Parameter accountIdentifier: 取得対象のアカウント識別子。
    /// - Returns: 開始日時が新しい順の接続セッション。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        storage.values
            .filter { $0.accountIdentifier == accountIdentifier }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
