import Foundation
import XCTest
@testable import ProjectZD8

/// 段階2の読み込みと段階3の状態の決定の結果を、解析用の読み込み結果へ写すアダプターを検証します(設計書 §3.7、§9 T4-9)。
///
/// 読み込みには実物の `LoadConnectionSessionLocationTrackUseCase` と段階2の Fake を使います。
/// 期待するルートは、別に検証済みの `DrivingRouteStatusResolver` で同じ取得結果から求めます。
@MainActor
final class RouteAnalysisTrackAdapterTests: XCTestCase {
    /// テストのアカウント識別子です。
    private let account = "account"
    /// ローカルの同期 Repository の Fake です。
    private let syncRepository = ConnectionSessionLocationTrackSyncRepositoryFake()
    /// iCloud の Repository の Fake です。
    private let cloudRepository = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 読み込みの closure が受け取った引数の記録です。
    private var receivedLoads: [String] = []

    /// 実物の読み込みユースケースを使うアダプターを作ります。
    ///
    /// 責務: Fake の Repository で組んだユースケースを、読み込みの closure として渡します。
    /// - Returns: アダプター。
    private func makeAdapter() -> RouteAnalysisTrackAdapter {
        let useCase = LoadConnectionSessionLocationTrackUseCase(syncRepository: syncRepository, cloudRepository: cloudRepository)
        return RouteAnalysisTrackAdapter(load: { sessionID, accountIdentifier in
            try await useCase.execute(sessionID: sessionID, accountIdentifier: accountIdentifier)
        })
    }

    /// 段階3の状態の決定で、期待するルートと注記を求めます。
    ///
    /// 責務: この端末で記録した軌跡の取得結果から、ルートと注記のキーを返します。
    /// - Parameter track: 軌跡。
    /// - Returns: 期待する読み込み結果。
    /// - Throws: ルートが無ければテスト失敗。
    private func expectedAvailable(for track: ConnectionSessionLocationTrack) throws -> RouteAnalysisTrackLoadResult {
        let status = DrivingRouteStatusResolver().status(for: .available(track, .recordedOnThisDevice))
        return .available(try XCTUnwrap(status.route), noticeKeys: status.noticeKeys)
    }

    /// 責務: この端末の点のある軌跡は、区切ったルートと空の注記の `available` になることを確かめます。
    func testLocalTrackWithPointsIsAvailable() async throws {
        let track = DrivingRouteTestValues.track(samples: try DrivingRouteTestValues.samples(count: 5))
        syncRepository.addSession(track, accountIdentifier: account)

        let result = try await makeAdapter().loadRoute(sessionID: track.sessionID, accountIdentifier: account)

        XCTAssertEqual(result, try expectedAvailable(for: track))
        guard case .available(let route, let noticeKeys) = result else { return XCTFail("available ではありません: \(result)") }
        XCTAssertEqual(route.points.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(noticeKeys, [])
    }

    /// 責務: 途中から記録した軌跡は、部分の注記のキーを持つ `available` になることを確かめます。
    func testPartialTrackCarriesNoticeKeys() async throws {
        let track = DrivingRouteTestValues.track(
            samples: try DrivingRouteTestValues.samples(count: 4),
            eventKinds: [.authorizationDenied, .recording]
        )
        syncRepository.addSession(track, accountIdentifier: account)

        let result = try await makeAdapter().loadRoute(sessionID: track.sessionID, accountIdentifier: account)

        XCTAssertEqual(result, try expectedAvailable(for: track))
        guard case .available(_, let noticeKeys) = result else { return XCTFail("available ではありません: \(result)") }
        XCTAssertEqual(noticeKeys, ["history.route.notice.partial.authorization_denied"])
    }

    /// 責務: iCloud から取得した軌跡も `available` になることを確かめます。
    func testCloudTrackIsAvailable() async throws {
        let track = DrivingRouteTestValues.track(samples: try DrivingRouteTestValues.samples(count: 3))
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: track.sessionID), accountIdentifier: account)
        cloudRepository.seedRecord(track, digest: ConnectionSessionLocationTrackTestValues.digest("a"), accountIdentifier: account)

        let result = try await makeAdapter().loadRoute(sessionID: track.sessionID, accountIdentifier: account)

        guard case .available(let route, _) = result else { return XCTFail("available ではありません: \(result)") }
        XCTAssertEqual(route.points.map(\.sequence), [0, 1, 2])
    }

    /// 責務: 事象だけの軌跡は、その事象の理由のキーと記号の `unavailable` になることを確かめます。
    func testEventsOnlyTrackIsUnavailableWithReason() async throws {
        let track = DrivingRouteTestValues.track(eventKinds: [.authorizationDenied])
        syncRepository.addSession(track, accountIdentifier: account)

        let result = try await makeAdapter().loadRoute(sessionID: track.sessionID, accountIdentifier: account)

        XCTAssertEqual(result, .unavailable(reasonKey: "history.route.absence.authorization_denied", systemImage: "location.slash"))
    }

    /// 責務: この端末にも iCloud にも無い軌跡は、notInCloud の理由の `unavailable` になることを確かめます。
    func testNotInCloudIsUnavailable() async throws {
        let sessionID = ConnectionSessionID()
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: sessionID), accountIdentifier: account)

        let result = try await makeAdapter().loadRoute(sessionID: sessionID, accountIdentifier: account)

        XCTAssertEqual(result, .unavailable(reasonKey: "history.route.absence.not_in_cloud", systemImage: "icloud.slash"))
    }

    /// 責務: 新しい版のアプリが作った軌跡(更新が必要)は、再試行できない失敗になることを確かめます。
    func testUnsupportedPayloadIsNonRetryableFailure() async throws {
        let sessionID = ConnectionSessionID()
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: sessionID), accountIdentifier: account)
        cloudRepository.setFailure(ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: 99), for: .download)

        let result = try await makeAdapter().loadRoute(sessionID: sessionID, accountIdentifier: account)

        XCTAssertEqual(result, .failed(messageKey: "history.route.failure.update_required", isRetryable: false))
    }

    /// 責務: 一般の失敗は、再試行できる読み込みの失敗になることを確かめます。
    func testGeneralFailureIsRetryable() async throws {
        let sessionID = ConnectionSessionID()
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: sessionID), accountIdentifier: account)
        syncRepository.setFailure(URLError(.cannotOpenFile), for: .track)

        let result = try await makeAdapter().loadRoute(sessionID: sessionID, accountIdentifier: account)

        XCTAssertEqual(result, .failed(messageKey: "history.route.failure.load", isRetryable: true))
    }

    /// 責務: 読み込みの取り消し(`CancellationError`)は、結果に変えずに投げ直すことを確かめます。
    func testCancellationIsRethrown() async {
        let sessionID = ConnectionSessionID()
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: sessionID), accountIdentifier: account)
        cloudRepository.setFailure(CancellationError(), for: .download)

        do {
            let result = try await makeAdapter().loadRoute(sessionID: sessionID, accountIdentifier: account)
            XCTFail("取り消しが投げ直されませんでした: \(result)")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// 責務: セッションとアカウント識別子を、そのまま読み込みへ渡すことを確かめます。
    func testPassesSessionAndAccountToLoad() async throws {
        let sessionID = ConnectionSessionID()
        let adapter = RouteAnalysisTrackAdapter(load: { [unowned self] id, accountIdentifier in
            receivedLoads.append("\(id == sessionID)-\(accountIdentifier)")
            return .notInCloud
        })

        _ = try await adapter.loadRoute(sessionID: sessionID, accountIdentifier: "someone")

        XCTAssertEqual(receivedLoads, ["true-someone"])
    }
}
