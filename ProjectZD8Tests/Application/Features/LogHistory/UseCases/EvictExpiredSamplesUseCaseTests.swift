import XCTest
@testable import ProjectZD8

final class EvictExpiredSamplesUseCaseTests: XCTestCase {
    private let now = RecordsFixtures.referenceDate
    private let day: TimeInterval = 86_400

    /// 終了が `age` 秒前のセッションを作ります。
    private func session(age: TimeInterval, digest: String? = "sha", availability: RawAvailability = .local, recording: Bool = false) -> DriveSession {
        RecordsFixtures.session(
            vehicleID: VehicleID(),
            startedAt: now.addingTimeInterval(-age - 100),
            duration: recording ? nil : 100,
            rawAvailability: availability,
            archiveDigest: digest
        )
    }

    private func run(_ sessions: [DriveSession], retention: LocalRawRetention) async throws -> (EvictExpiredSamplesUseCase.Result, RecordsFakeSessionRepository) {
        let repo = RecordsFakeSessionRepository(sessions: sessions)
        let store = RecordsFakeSettingsStore(settings: AppSettings(localRawRetention: retention))
        let now = now
        let result = try await EvictExpiredSamplesUseCase(sessions: repo, settings: store, now: { now }).execute()
        return (result, repo)
    }

    func testRetentionBoundaryIsStrictlyOlderThan() async throws {
        let exactly = session(age: 30 * day)
        let older = session(age: 30 * day + 1)
        let newer = session(age: 30 * day - 1)
        let (result, repo) = try await run([exactly, older, newer], retention: .days30)
        XCTAssertEqual(result.evicted, [older.id])
        XCTAssertEqual(repo.evictedIDs, [older.id])
        XCTAssertTrue(result.failed.isEmpty)
    }

    func testNinetyDayRetention() async throws {
        let a = session(age: 60 * day)
        let b = session(age: 91 * day)
        let (result, _) = try await run([a, b], retention: .days90)
        XCTAssertEqual(result.evicted, [b.id])
    }

    func testUnlimitedRetentionEvictsNothing() async throws {
        let (result, repo) = try await run([session(age: 1000 * day)], retention: .unlimited)
        XCTAssertTrue(result.evicted.isEmpty)
        XCTAssertTrue(repo.evictedIDs.isEmpty)
    }

    func testSkipsNotUploadedRecordingAndAlreadyCloudOnly() async throws {
        let notUploaded = session(age: 100 * day, digest: nil)
        let recording = session(age: 100 * day, recording: true)
        let cloudOnly = session(age: 100 * day, availability: .cloudOnly)
        let (result, repo) = try await run([notUploaded, recording, cloudOnly], retention: .days30)
        XCTAssertTrue(result.evicted.isEmpty)
        XCTAssertTrue(repo.evictedIDs.isEmpty)
    }

    func testReportsFailuresAndContinues() async throws {
        let bad = session(age: 100 * day)
        let good = session(age: 100 * day)
        let repo = RecordsFakeSessionRepository(sessions: [bad, good])
        repo.failEviction(of: bad.id)
        let store = RecordsFakeSettingsStore(settings: AppSettings(localRawRetention: .days30))
        let now = now
        let result = try await EvictExpiredSamplesUseCase(sessions: repo, settings: store, now: { now }).execute()
        XCTAssertEqual(result.failed, [bad.id])
        XCTAssertEqual(result.evicted, [good.id])
    }

    func testListFailureThrows() async {
        let repo = RecordsFakeSessionRepository()
        repo.setListError(.ioFailure)
        let store = RecordsFakeSettingsStore(settings: AppSettings(localRawRetention: .days30))
        do {
            _ = try await EvictExpiredSamplesUseCase(sessions: repo, settings: store).execute()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? StoreError, .ioFailure)
        }
    }
}
