import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの取得ユースケースが、ローカルの状態と iCloud の状態に応じて、取得・復元・出どころの値を仕様どおりに返すことを検証します。
@MainActor
final class LoadConnectionSessionLocationTrackUseCaseTests: XCTestCase {
    /// テストで注入するエラーです。
    private enum InjectedError: Error, Equatable {
        /// iCloud の失敗です。
        case cloud
        /// ローカルの失敗です。
        case local
    }

    /// 取得するアカウントです。
    private static let account = "account-a"
    /// ユースケースへ注入する現在時刻です。
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    /// ローカルの同期 Repository の Fake です。
    private let sync = ConnectionSessionLocationTrackSyncRepositoryFake()
    /// iCloud の Repository の Fake です。
    private let cloud = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 取得対象のセッションです。
    private let sessionID = ConnectionSessionID()

    /// この端末で記録して同期記録が無いなら、通信せずにローカルを返します。
    ///
    /// 責務: `recordedOnThisDevice` とローカルの軌跡が返り、iCloud の呼び出しが0回であることを確認します。
    func testLocalTrackWithoutSyncRecordIsRecordedOnThisDeviceWithoutCloudCalls() async throws {
        let local = try track(sampleCount: 3, eventCount: 1)
        sync.addSession(local, accountIdentifier: Self.account)

        let availability = try await execute()

        XCTAssertEqual(availability, .available(local, .recordedOnThisDevice))
        XCTAssertEqual(cloud.calls, [])
        XCTAssertEqual(sync.replaceCalls, [])
    }

    /// この端末で記録して送信済みなら、通信せずにローカルを返します。
    ///
    /// 責務: uploaded の同期記録があっても `recordedOnThisDevice` で、iCloud の呼び出しが0回であることを確認します。
    func testUploadedLocalTrackIsRecordedOnThisDeviceWithoutCloudCalls() async throws {
        let local = try track(sampleCount: 2)
        sync.addSession(local, accountIdentifier: Self.account, syncRecord: record(.uploaded, digest: "a", track: local))
        try seedRemote(sampleCount: 5, digest: "f")

        let availability = try await execute()

        XCTAssertEqual(availability, .available(local, .recordedOnThisDevice))
        XCTAssertEqual(cloud.calls, [])
    }

    /// 復元済みで digest が同じなら、取得せずに最新と確認できたローカルを返します。
    ///
    /// 責務: `restoredEarlier(isVerifiedLatest: true)` が返り、download も置き換えも行わないことを確認します。
    func testRestoredWithSameDigestIsVerifiedLatestWithoutDownload() async throws {
        let local = try track(sampleCount: 2)
        sync.addSession(local, accountIdentifier: Self.account, syncRecord: record(.restored, digest: "c", track: local))
        cloud.seedRecord(local, digest: digest("c"), accountIdentifier: Self.account)

        let availability = try await execute()

        XCTAssertEqual(availability, .available(local, .restoredEarlier(isVerifiedLatest: true)))
        XCTAssertEqual(cloud.calls, [.remoteManifest(sessionID: sessionID, accountIdentifier: Self.account)])
        XCTAssertEqual(sync.replaceCalls, [])
    }

    /// 復元済みで digest が違うなら、取得して置き換え、新しい軌跡を `downloadedNow` で返します。
    ///
    /// 責務: download が呼ばれ、取得した軌跡・digest・現在時刻で置き換えられ、返る軌跡が新しい方であることを確認します。
    func testRestoredWithDifferentDigestDownloadsAndReplaces() async throws {
        let local = try track(sampleCount: 2)
        sync.addSession(local, accountIdentifier: Self.account, syncRecord: record(.restored, digest: "c", track: local))
        let remote = try seedRemote(sampleCount: 4, digest: "d")

        let availability = try await execute()

        XCTAssertEqual(availability, .available(remote, .downloadedNow))
        XCTAssertTrue(cloud.calls.contains(.download(sessionID: sessionID, accountIdentifier: Self.account)))
        let verified = VerifiedConnectionSessionLocationTrack(track: remote, manifestDigest: digest("d"))
        XCTAssertEqual(sync.replaceCalls, [.replaceWithRestoredTrack(verified, date: Self.now)])
        XCTAssertEqual(sync.storedTrack(for: sessionID), remote)
    }

    /// 復元済みで概要の取得が失敗したら、最新か確認できていないローカルを返します。
    ///
    /// 責務: 失敗を成功に潰さず `restoredEarlier(isVerifiedLatest: false)` で返し、置き換えないことを確認します。
    func testRestoredWithManifestFailureIsNotVerifiedLatest() async throws {
        let local = try track(sampleCount: 2)
        sync.addSession(local, accountIdentifier: Self.account, syncRecord: record(.restored, digest: "c", track: local))
        try seedRemote(sampleCount: 4, digest: "d")
        cloud.setFailure(InjectedError.cloud, for: .remoteManifest)

        let availability = try await execute()

        XCTAssertEqual(availability, .available(local, .restoredEarlier(isVerifiedLatest: false)))
        XCTAssertEqual(sync.replaceCalls, [])
    }

    /// 復元済みで iCloud にレコードが無いなら、最新か確認できていないローカルを返します。
    ///
    /// 責務: レコードが無い時に `restoredEarlier(isVerifiedLatest: false)` で返し、download も置き換えもしないことを確認します。
    func testRestoredWithoutRemoteRecordIsNotVerifiedLatest() async throws {
        let local = try track(sampleCount: 2)
        sync.addSession(local, accountIdentifier: Self.account, syncRecord: record(.restored, digest: "c", track: local))

        let availability = try await execute()

        XCTAssertEqual(availability, .available(local, .restoredEarlier(isVerifiedLatest: false)))
        XCTAssertFalse(cloud.calls.contains(.download(sessionID: sessionID, accountIdentifier: Self.account)))
        XCTAssertEqual(sync.replaceCalls, [])
    }

    /// ローカルが空で iCloud にも無ければ `notInCloud` を返し、何も書きません。
    ///
    /// 責務: 空データと区別した値で返り、置き換えも送信済みの記録も呼ばないことを確認します。
    func testEmptyLocalWithoutRemoteRecordIsNotInCloudAndWritesNothing() async throws {
        sync.addSession(ConnectionSessionLocationTrackTestValues.emptyTrack(sessionID: sessionID), accountIdentifier: Self.account)

        let availability = try await execute()

        XCTAssertEqual(availability, .notInCloud)
        XCTAssertTrue(cloud.calls.contains(.download(sessionID: sessionID, accountIdentifier: Self.account)))
        XCTAssertEqual(sync.replaceCalls, [])
        XCTAssertEqual(sync.markUploadedCalls, [])
        XCTAssertNil(sync.storedSyncRecord(for: sessionID))
    }

    /// ローカルが空で iCloud から取得できたら、復元して `downloadedNow` で返します。
    ///
    /// 責務: 取得した軌跡・digest・現在時刻で置き換えられ、restored の同期記録になることを確認します。
    func testEmptyLocalWithRemoteRecordIsRestoredAndDownloadedNow() async throws {
        sync.addSession(ConnectionSessionLocationTrackTestValues.emptyTrack(sessionID: sessionID), accountIdentifier: Self.account)
        let remote = try seedRemote(sampleCount: 3, eventCount: 2, digest: "e")

        let availability = try await execute()

        XCTAssertEqual(availability, .available(remote, .downloadedNow))
        let verified = VerifiedConnectionSessionLocationTrack(track: remote, manifestDigest: digest("e"))
        XCTAssertEqual(sync.replaceCalls, [.replaceWithRestoredTrack(verified, date: Self.now)])
        XCTAssertEqual(sync.storedSyncRecord(for: sessionID)?.origin, .restored)
    }

    /// ローカルが空で取得が失敗したら、空として返さずにそのエラーを投げます。
    ///
    /// 責務: download のエラーがそのまま伝わり、何も書かれないことを確認します。
    func testEmptyLocalWithDownloadFailureThrows() async throws {
        sync.addSession(ConnectionSessionLocationTrackTestValues.emptyTrack(sessionID: sessionID), accountIdentifier: Self.account)
        cloud.setFailure(InjectedError.cloud, for: .download)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .cloud)
        XCTAssertEqual(sync.replaceCalls, [])
    }

    /// ローカルの読み取りが失敗したら、空として扱わずにそのエラーを投げます。
    ///
    /// 責務: 軌跡の読み取りのエラーがそのまま伝わり、iCloud から取得しに行かないことを確認します。
    func testLocalReadFailureThrowsWithoutDownload() async throws {
        sync.addSession(try track(sampleCount: 2), accountIdentifier: Self.account)
        sync.setFailure(InjectedError.local, for: .track)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .local)
        XCTAssertFalse(cloud.calls.contains(.download(sessionID: sessionID, accountIdentifier: Self.account)))
    }

    /// 空のアカウントは不正な状態として失敗し、ローカルも iCloud も呼びません。
    ///
    /// 責務: 空文字のアカウントで `invalidState` が投げられ、呼び出しが0件であることを確認します。
    func testEmptyAccountThrowsInvalidStateWithoutAnyCall() async throws {
        sync.addSession(try track(sampleCount: 2), accountIdentifier: Self.account)

        let error = await executeExpectingError(accountIdentifier: "")

        XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        XCTAssertEqual(sync.calls, [])
        XCTAssertEqual(cloud.calls, [])
    }

    /// 対象のセッションを取得します。
    ///
    /// 責務: Fake と固定の現在時刻を注入したユースケースを、取得するアカウントで実行します。
    /// - Returns: 取得の結果。
    /// - Throws: ユースケースが投げたエラー。
    private func execute() async throws -> ConnectionSessionLocationTrackAvailability {
        try await makeUseCase().execute(sessionID: sessionID, accountIdentifier: Self.account)
    }

    /// 失敗するはずの取得を行い、投げられたエラーを返します。
    ///
    /// 責務: 成功した場合はテストを失敗させ、`nil` を返します。
    /// - Parameter accountIdentifier: 取得するアカウント。`nil` なら取得するアカウント。
    /// - Returns: 投げられたエラー。成功した場合は `nil`。
    private func executeExpectingError(accountIdentifier: String? = nil) async -> (any Error)? {
        do {
            let availability = try await makeUseCase().execute(
                sessionID: sessionID,
                accountIdentifier: accountIdentifier ?? Self.account
            )
            XCTFail("取得は失敗する必要があります: \(availability)")
            return nil
        } catch {
            return error
        }
    }

    /// テスト対象のユースケースを作ります。
    ///
    /// 責務: Fake と固定の現在時刻を注入します。
    /// - Returns: 取得ユースケース。
    private func makeUseCase() -> LoadConnectionSessionLocationTrackUseCase {
        LoadConnectionSessionLocationTrackUseCase(syncRepository: sync, cloudRepository: cloud, now: { Self.now })
    }

    /// 対象セッションの軌跡を作ります。
    ///
    /// 責務: 指定件数のサンプルと事象を持つ軌跡を返します。
    /// - Parameters:
    ///   - sampleCount: サンプル件数。
    ///   - eventCount: 事象件数。
    ///   - sampleOffset: 位置の値をずらす量。
    /// - Returns: 軌跡。
    /// - Throws: 軌跡を作れない場合のテスト失敗。
    private func track(sampleCount: Int, eventCount: Int = 0, sampleOffset: Int = 0) throws -> ConnectionSessionLocationTrack {
        try ConnectionSessionLocationTrackTestValues.track(
            sessionID: sessionID,
            sampleCount: sampleCount,
            eventCount: eventCount,
            sampleOffset: sampleOffset
        )
    }

    /// 対象セッションの同期記録を作ります。
    ///
    /// 責務: 軌跡の水位を記録した同期記録を返します。
    /// - Parameters:
    ///   - origin: 由来。
    ///   - digest: digest の文字(64回繰り返します)。
    ///   - track: 水位を取る軌跡。
    /// - Returns: 同期記録。
    private func record(
        _ origin: ConnectionSessionLocationTrackSyncOrigin,
        digest character: Character,
        track: ConnectionSessionLocationTrack
    ) -> ConnectionSessionLocationTrackSyncRecord {
        ConnectionSessionLocationTrackTestValues.syncRecord(
            sessionID: sessionID,
            origin: origin,
            digest: digest(character),
            watermark: track.watermark
        )
    }

    /// 1文字を64回繰り返した digest を返します。
    ///
    /// 責務: テスト値の digest の作り方を1か所にまとめます。
    /// - Parameter character: 繰り返す文字。
    /// - Returns: digest。
    private func digest(_ character: Character) -> String {
        ConnectionSessionLocationTrackTestValues.digest(character)
    }

    /// 対象セッションのリモートのレコードを置きます(ローカルとは位置の値が違う軌跡)。
    ///
    /// 責務: 他の端末が送った新しい内容の状況を作ります。
    /// - Parameters:
    ///   - sampleCount: サンプル件数。
    ///   - eventCount: 事象件数。
    ///   - character: digest の文字。
    /// - Returns: 置いた軌跡。
    /// - Throws: 軌跡を作れない場合のテスト失敗。
    @discardableResult
    private func seedRemote(sampleCount: Int, eventCount: Int = 0, digest character: Character) throws -> ConnectionSessionLocationTrack {
        let remote = try track(sampleCount: sampleCount, eventCount: eventCount, sampleOffset: 100)
        cloud.seedRecord(remote, digest: digest(character), accountIdentifier: Self.account)
        return remote
    }
}
