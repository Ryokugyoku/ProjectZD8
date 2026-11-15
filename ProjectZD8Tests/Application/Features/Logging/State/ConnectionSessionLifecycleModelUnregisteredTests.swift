import Foundation
import XCTest
@testable import ProjectZD8

/// 未登録車両の接続でセッションを車両なしで始め、途中で登録した車両を同じセッションへ結び付け、プロセス復帰の続行を判定することを検証します。
@MainActor
final class ConnectionSessionLifecycleModelUnregisteredTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)
    /// 登録済みの車両です。
    private let vehicle = VehicleProfile(id: VehicleID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!), vin: "VIN", name: "BRZ")

    /// 未登録車両の接続では、車両なしの接続セッションが作られて保存されます。
    ///
    /// 責務: 開始要求と未登録の確定で、車両なしの現在セッションができることを確認します。
    func testUnregisteredConnectionStartsSessionWithoutVehicle() throws {
        let fixture = try Fixture(storage: .grdb)
        let model = makeModel(fixture, dates: ManualDateClock(Date(timeIntervalSince1970: 3_000)))
        model.send(.accountIdentifierChanged("other"))

        model.send(.startRequested)
        model.send(.vehicleUnregistered)

        let session = try XCTUnwrap(model.activeSession)
        XCTAssertNil(session.vehicle)
        XCTAssertEqual(try fixture.sessions.sessions(for: "other").map(\.id), [session.id])
    }

    /// 途中で登録した車両は、セッションを切り替えずに同じセッションへ結び付き、既に車両があるセッションは変えません。
    ///
    /// 責務: 同じセッションIDのまま車両が保存されることと、2回目の登録通知で車両が置き換わらないことを確認します。
    func testLaterRegisteredVehicleBindsToSameSession() throws {
        let fixture = try Fixture(storage: .grdb)
        let model = makeModel(fixture, dates: ManualDateClock(Date(timeIntervalSince1970: 3_000)))
        model.send(.accountIdentifierChanged("other"))
        model.send(.startRequested)
        model.send(.vehicleUnregistered)
        let started = try XCTUnwrap(model.activeSession)

        model.send(.unregisteredVehicleRegistered(vehicle))
        model.send(.unregisteredVehicleRegistered(VehicleProfile(vin: "OTHER", name: "Other")))

        XCTAssertEqual(model.activeSession?.id, started.id)
        XCTAssertEqual(model.activeSession?.vehicle?.id, vehicle.id)
        XCTAssertEqual(try fixture.sessions.sessions(for: "other").first { $0.id == started.id }?.vehicle?.id, vehicle.id)
        XCTAssertEqual(try fixture.sessions.sessions(for: "other").count, 1)
    }

    /// 未登録車両のセッションは、猶予内のプロセス復帰の後に未登録車両で接続すると続行します。
    ///
    /// 責務: 車両なし同士の一致で同じセッションを続け、セッションが終了しないことを確認します。
    func testUnregisteredSessionResumesWithUnregisteredConnection() async throws {
        let (fixture, dates) = try await makeInterruptedUnregistered()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        XCTAssertNil(model.activeSession)

        dates.set(lastCommittedAt.addingTimeInterval(90))
        model.send(.vehicleUnregistered)

        XCTAssertEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertNil(try stored(fixture).endedAt)
    }

    /// 未登録車両のセッションは、登録済み車両の接続では続けず、最後のcommitの時刻で終了して新しいセッションを作ります。
    ///
    /// 責務: 未登録と登録済みの不一致で続行しないことを確認します。
    func testUnregisteredSessionEndsWithRegisteredConnection() async throws {
        let (fixture, dates) = try await makeInterruptedUnregistered()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        model.send(.vehicleResolved(vehicle))

        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertEqual(model.activeSession?.vehicle?.id, vehicle.id)
    }

    /// 未登録車両のセッションも、未登録車両の接続までに猶予を過ぎていれば終了して新しいセッションを作ります。
    ///
    /// 責務: 車両なし同士でも実時間の猶予切れで続行しないことを確認します。
    func testUnregisteredSessionEndsWhenGraceExpires() async throws {
        let (fixture, dates) = try await makeInterruptedUnregistered()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        dates.set(lastCommittedAt.addingTimeInterval(181))
        model.send(.vehicleUnregistered)

        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertNil(model.activeSession?.vehicle)
    }

    /// 車両なしのセッションに2周回を記録してcommitし、終了せずにプロセスが終わった状態を作ります。
    ///
    /// 責務: 最後のRawの実時刻を `lastCommittedAt` にした未終了の車両なしセッションと、モデルへ渡す実時刻clockを返します。
    /// - Returns: GRDBの部品と実時刻clock。
    /// - Throws: 記録の失敗。
    private func makeInterruptedUnregistered() async throws -> (Fixture, ManualDateClock) {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        fixture.dates.set(Date(timeIntervalSince1970: 1_010))
        try await fixture.respondedRound(0, payload: 10)
        fixture.dates.set(lastCommittedAt)
        try await fixture.respondedRound(1, payload: 20)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        XCTAssertNil(try stored(fixture).vehicle)
        return (fixture, ManualDateClock(lastCommittedAt))
    }

    /// 部品のGRDBを使うライフサイクルモデルを作ります。
    ///
    /// 責務: 本番の組立と同じRepositoryの組合せと実時刻clockでモデルを返します。
    /// - Parameters:
    ///   - fixture: GRDBの部品。
    ///   - dates: 実時刻clock。
    /// - Returns: ライフサイクルモデル。
    private func makeModel(_ fixture: Fixture, dates: ManualDateClock) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: fixture.sessions,
            rawLogRepository: fixture.sessions,
            acquisitionTerminationRepository: fixture.acquisition,
            now: { dates.now() },
            recoverRelaunchedSession: RecoverRelaunchedConnectionSessionUseCase(
                rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
                gapRepository: fixture.gaps, terminationRepository: fixture.acquisition
            )
        )
    }

    /// 部品のセッションを読み戻します。
    ///
    /// 責務: 部品のセッションIDのセッションを返します。
    /// - Parameter fixture: GRDBの部品。
    /// - Returns: セッション。
    /// - Throws: 読込失敗、またはセッションが無い場合のエラー。
    private func stored(_ fixture: Fixture) throws -> ConnectionSession {
        try XCTUnwrap(fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID })
    }
}
