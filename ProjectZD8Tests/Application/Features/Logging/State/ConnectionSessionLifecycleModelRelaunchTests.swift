import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス復帰後のアカウント有効化で、未終了セッションを続行・終了し、指定された終了時刻でセッションを終えることを検証します。
@MainActor
final class ConnectionSessionLifecycleModelRelaunchTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)
    /// 中断したセッションの車両です。
    private let vehicle = VehicleProfile(id: VehicleID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!), vin: "VIN", name: "BRZ")

    /// 猶予内に同じ車両で接続すると、新しいセッションを作らずに中断したセッションを続行します。
    ///
    /// 責務: 開始要求では判定を保留し、同じ車両の確定で同じセッションIDが現在のセッションになることを確認します。
    func testSameVehicleWithinGraceResumesSameSession() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        XCTAssertNil(model.activeSession)

        dates.set(lastCommittedAt.addingTimeInterval(180))
        model.send(.vehicleResolved(vehicle))

        XCTAssertEqual(model.activeSession?.id, fixture.sessionID)
        XCTAssertNil(try stored(fixture).endedAt)
    }

    /// 別の車両で接続すると、中断したセッションを最後のcommitの時刻で終了し、新しいセッションを作ります。
    ///
    /// 責務: 車両が違う場合の終了時刻と、新しいセッションの作成を確認します。
    func testDifferentVehicleEndsOldSessionAndCreatesNew() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        model.send(.vehicleResolved(VehicleProfile(vin: "OTHER", name: "Other")))

        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
        XCTAssertNotNil(model.activeSession)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
    }

    /// 同じ車両でも、車両の確定までに猶予を過ぎていれば中断したセッションを終了して新しいセッションを作ります。
    ///
    /// 責務: 車両の確定時の実時刻で猶予を判定し直すことを確認します。
    func testGraceExpiringBeforeVehicleResolutionEndsOldSession() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        dates.set(lastCommittedAt.addingTimeInterval(181))
        model.send(.vehicleResolved(vehicle))

        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
    }

    /// アカウント有効化の時点で猶予を過ぎていれば、中断したセッションはその場で最後のcommitの時刻で終了し、開始要求ですぐ新しいセッションを作ります。
    ///
    /// 責務: 猶予切れの復帰でセッションが終了し、判定を保留しないことを確認します。
    func testExpiredAtActivationEndsSessionImmediately() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(500))

        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        XCTAssertEqual(try stored(fixture).endedAt, lastCommittedAt)
        XCTAssertNotNil(model.activeSession)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
    }

    /// 未終了セッションが無ければ、アカウント有効化で欠損を記録しません。
    ///
    /// 責務: 終了済みのセッションだけのアカウントで復帰処理が何も記録しないことを確認します。
    func testNoUnfinishedSessionRecordsNothing() async throws {
        let (fixture, dates) = try await makeInterrupted()
        _ = try fixture.acquisition.finishSessionAcquisition(try stored(fixture), endedAt: lastCommittedAt, reason: .userDisconnected)
        let model = makeModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID), [])
    }

    /// 復帰処理の保存に失敗したセッションは、続行も終了もされずに未終了のまま残り、開始要求では新しいセッションを作ります。
    ///
    /// 責務: 復帰処理の失敗を続行可能や終了済みと扱わないことを確認します。
    func testRecoveryFailureNeitherResumesNorEnds() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let failing = RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
            gapRepository: AcquisitionGapRepositorySpy(failsSave: true), terminationRepository: fixture.acquisition
        )
        let model = makeModel(fixture, dates: dates, recovery: failing)
        dates.set(lastCommittedAt.addingTimeInterval(30))

        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)

        XCTAssertNil(try stored(fixture).endedAt)
        XCTAssertNotNil(model.activeSession)
        XCTAssertNotEqual(model.activeSession?.id, fixture.sessionID)
    }

    /// 終了要求に終了時刻が指定されていればその時刻で、開始より前なら開始時刻で終了します。
    ///
    /// 責務: 猶予切れの終了時刻(最後に正常応答を受けた実時刻)がセッションの終了時刻になることを確認します。
    func testEndRequestedUsesGivenEndTimeClampedToStart() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeModel(fixture, dates: dates)
        dates.set(Date(timeIntervalSince1970: 3_000))
        model.send(.accountIdentifierChanged("other"))
        model.send(.startRequested)
        let first = try XCTUnwrap(model.activeSession)
        model.send(.endRequested(.connectionLost, endedAt: Date(timeIntervalSince1970: 3_500)))
        model.send(.startRequested)
        let second = try XCTUnwrap(model.activeSession)

        model.send(.endRequested(.vehicleNoResponse, endedAt: Date(timeIntervalSince1970: 2_000)))

        let sessions = try fixture.sessions.sessions(for: "other")
        XCTAssertEqual(sessions.first { $0.id == first.id }?.endedAt, Date(timeIntervalSince1970: 3_500))
        XCTAssertEqual(sessions.first { $0.id == first.id }?.endReason, .connectionLost)
        XCTAssertEqual(sessions.first { $0.id == second.id }?.endedAt, second.startedAt)
    }

    /// 車両付きのセッションに2周回を記録してcommitし、終了せずにプロセスが終わった状態を作ります。
    ///
    /// 責務: 最後のRawの実時刻を `lastCommittedAt` にした未終了セッションと、モデルへ渡す実時刻clockを返します。
    /// - Returns: GRDBの部品と実時刻clock。
    /// - Throws: 記録の失敗。
    private func makeInterrupted() async throws -> (Fixture, ManualDateClock) {
        let fixture = try Fixture(storage: .grdb)
        var session = try stored(fixture)
        session.vehicle = ConnectionSessionVehicle(profile: vehicle)
        try fixture.sessions.save(session)
        try await fixture.start()
        fixture.dates.set(Date(timeIntervalSince1970: 1_010))
        try await fixture.respondedRound(0, payload: 10)
        fixture.dates.set(lastCommittedAt)
        try await fixture.respondedRound(1, payload: 20)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        return (fixture, ManualDateClock(lastCommittedAt))
    }

    /// 部品のGRDBを使うライフサイクルモデルを作ります。
    ///
    /// 責務: 本番の組立と同じRepositoryの組合せと、指定の復帰処理・実時刻clockでモデルを返します。
    /// - Parameters:
    ///   - fixture: GRDBの部品。
    ///   - dates: 実時刻clock。
    ///   - recovery: 復帰処理。`nil` なら部品のGRDBを使う復帰処理。
    /// - Returns: ライフサイクルモデル。
    private func makeModel(
        _ fixture: Fixture,
        dates: ManualDateClock,
        recovery: RecoverRelaunchedConnectionSessionUseCase? = nil
    ) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: fixture.sessions,
            rawLogRepository: fixture.sessions,
            acquisitionTerminationRepository: fixture.acquisition,
            now: { dates.now() },
            recoverRelaunchedSession: recovery ?? RecoverRelaunchedConnectionSessionUseCase(
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
