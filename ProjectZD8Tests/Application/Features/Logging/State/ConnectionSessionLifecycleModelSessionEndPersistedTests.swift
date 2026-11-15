import Foundation
import XCTest
@testable import ProjectZD8

/// セッションの終了を保存できた全経路で、自動アップロード設定に関係なく `sessionEndPersisted` が
/// 終了したセッションごとに1回呼ばれ、保存に失敗したときは呼ばれないことを検証します。
@MainActor
final class ConnectionSessionLifecycleModelSessionEndPersistedTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)
    /// 中断したセッションの車両です。
    private let vehicle = VehicleProfile(id: VehicleID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!), vin: "VIN", name: "BRZ")
    /// `sessionEndPersisted` へ渡されたセッションIDです。
    private var persistedEnds: [ConnectionSessionID] = []
    /// `endedSessionUploadRequested` へ渡されたセッションIDです。
    private var uploadRequests: [ConnectionSessionID] = []

    /// 通常の終了要求で、自動アップロードがオフでも1回呼ばれ、アップロード要求は出ません。
    ///
    /// 責務: 通常終了・オフの経路を確認します。
    func testEndRequestNotifiesOnceWhileAutomaticUploadOff() throws {
        let model = makeSimpleModel(repository: SavingConnectionSessionRepositorySpy(), automaticUploadEnabled: false)
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        let sessionID = try XCTUnwrap(model.activeSession?.id)

        model.send(.endRequested(.userDisconnected))

        XCTAssertEqual(persistedEnds, [sessionID])
        XCTAssertEqual(uploadRequests, [])
    }

    /// 通常の終了要求で、自動アップロードがオンなら1回呼ばれ、従来どおりアップロード要求も1回出ます。
    ///
    /// 責務: 通常終了・オンの経路を確認します。
    func testEndRequestNotifiesOnceWhileAutomaticUploadOn() throws {
        let model = makeSimpleModel(repository: SavingConnectionSessionRepositorySpy(), automaticUploadEnabled: true)
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        let sessionID = try XCTUnwrap(model.activeSession?.id)

        model.send(.endRequested(.userDisconnected))

        XCTAssertEqual(persistedEnds, [sessionID])
        XCTAssertEqual(uploadRequests, [sessionID])
    }

    /// 終了の保存に失敗したら呼ばれません(アップロード要求も出ません)。
    ///
    /// 責務: 通常終了の保存失敗を確認します。
    func testEndSaveFailureDoesNotNotify() throws {
        let repository = SavingConnectionSessionRepositorySpy()
        let model = makeSimpleModel(repository: repository, automaticUploadEnabled: true)
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        XCTAssertNotNil(model.activeSession)
        repository.failsSave = true

        model.send(.endRequested(.userDisconnected))

        XCTAssertEqual(persistedEnds, [])
        XCTAssertEqual(uploadRequests, [])
    }

    /// アカウント有効化時の未終了セッションの回収で、回収したセッションごとに1回呼ばれます(オフ・オンとも)。
    ///
    /// 責務: 復帰処理を持たない回収の経路を、2件のセッションと両方の設定で確認します。
    func testAccountActivationRecoveryNotifiesEachRecoveredSession() throws {
        for automaticUploadEnabled in [false, true] {
            persistedEnds = []
            uploadRequests = []
            let fixture = try Fixture()
            let second = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 5))
            try fixture.sessions.save(second)
            let model = makeSimpleModel(repository: fixture.sessions, automaticUploadEnabled: automaticUploadEnabled)

            model.send(.accountIdentifierChanged("account"))

            let expected: Set<ConnectionSessionID> = [fixture.sessionID, second.id]
            XCTAssertEqual(persistedEnds.count, 2, "automaticUploadEnabled=\(automaticUploadEnabled)")
            XCTAssertEqual(Set(persistedEnds), expected, "automaticUploadEnabled=\(automaticUploadEnabled)")
            XCTAssertEqual(Set(uploadRequests), automaticUploadEnabled ? expected : [])
        }
    }

    /// プロセス復帰の時点で猶予を過ぎていたセッションの終了で、オフでも1回呼ばれます。
    ///
    /// 責務: 復帰処理による回収の経路を確認します。
    func testRelaunchExpiredAtActivationNotifiesOnce() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeRelaunchModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(500))

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(persistedEnds, [fixture.sessionID])
        XCTAssertEqual(uploadRequests, [])
    }

    /// プロセス復帰後、別の車両で接続して続行できず終了した場合に、終了したセッションについて1回呼ばれます。
    ///
    /// 責務: 続行不可による終了の経路を確認します。
    func testRelaunchedSessionEndedOnDifferentVehicleNotifiesOnce() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let model = makeRelaunchModel(fixture, dates: dates)
        dates.set(lastCommittedAt.addingTimeInterval(30))
        model.send(.accountIdentifierChanged("account"))
        model.send(.startRequested)
        XCTAssertEqual(persistedEnds, [])

        model.send(.vehicleResolved(VehicleProfile(vin: "OTHER", name: "Other")))

        XCTAssertEqual(persistedEnds, [fixture.sessionID])
        XCTAssertEqual(uploadRequests, [])
    }

    /// プロセス復帰の処理で保存に失敗したセッションについては呼ばれません。
    ///
    /// 責務: 復帰処理の保存失敗を確認します。
    func testRelaunchRecoveryFailureDoesNotNotify() async throws {
        let (fixture, dates) = try await makeInterrupted()
        let failing = RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
            gapRepository: AcquisitionGapRepositorySpy(failsSave: true), terminationRepository: fixture.acquisition
        )
        let model = makeRelaunchModel(fixture, dates: dates, recovery: failing)
        dates.set(lastCommittedAt.addingTimeInterval(500))

        model.send(.accountIdentifierChanged("account"))

        XCTAssertEqual(persistedEnds, [])
    }

    /// 復帰処理を持たないモデルを、通知の記録先へ結び付けて作ります。
    ///
    /// 責務: 2つの通知をこのテストの記録へ結び付けたモデルを返します。
    /// - Parameters:
    ///   - repository: セッションの保存先。
    ///   - automaticUploadEnabled: 自動アップロードの初期値。
    /// - Returns: ライフサイクルモデル。
    private func makeSimpleModel(
        repository: any ConnectionSessionRepository,
        automaticUploadEnabled: Bool
    ) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: repository,
            automaticUploadEnabled: automaticUploadEnabled,
            endedSessionUploadRequested: { [unowned self] in uploadRequests.append($0.id) },
            sessionEndPersisted: { [unowned self] in persistedEnds.append($0.id) }
        )
    }

    /// 部品のGRDBと復帰処理を使い、通知の記録先へ結び付けたモデルを作ります(自動アップロードはオフ)。
    ///
    /// 責務: 本番の組立と同じRepositoryの組合せで、2つの通知をこのテストの記録へ結び付けたモデルを返します。
    /// - Parameters:
    ///   - fixture: GRDBの部品。
    ///   - dates: 実時刻clock。
    ///   - recovery: 復帰処理。`nil` なら部品のGRDBを使う復帰処理。
    /// - Returns: ライフサイクルモデル。
    private func makeRelaunchModel(
        _ fixture: Fixture,
        dates: ManualDateClock,
        recovery: RecoverRelaunchedConnectionSessionUseCase? = nil
    ) -> ConnectionSessionLifecycleModel {
        ConnectionSessionLifecycleModel(
            repository: fixture.sessions,
            rawLogRepository: fixture.sessions,
            acquisitionTerminationRepository: fixture.acquisition,
            now: { dates.now() },
            endedSessionUploadRequested: { [unowned self] in uploadRequests.append($0.id) },
            sessionEndPersisted: { [unowned self] in persistedEnds.append($0.id) },
            recoverRelaunchedSession: recovery ?? RecoverRelaunchedConnectionSessionUseCase(
                rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
                gapRepository: fixture.gaps, terminationRepository: fixture.acquisition
            )
        )
    }

    /// 車両付きのセッションに2周回を記録してcommitし、終了せずにプロセスが終わった状態を作ります。
    ///
    /// 責務: 最後のRawの実時刻を `lastCommittedAt` にした未終了セッションと、モデルへ渡す実時刻clockを返します。
    /// - Returns: GRDBの部品と実時刻clock。
    /// - Throws: 記録の失敗。
    private func makeInterrupted() async throws -> (Fixture, ManualDateClock) {
        let fixture = try Fixture(storage: .grdb)
        var session = try XCTUnwrap(fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID })
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
}
