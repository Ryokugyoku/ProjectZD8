import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの詳細のモデルを、実物の読み込みユースケースとフェイクのリポジトリで組み立てます。
///
/// 読み込みの closure は、記録 → 門で待つ → 実物の `LoadConnectionSessionLocationTrackUseCase` の順に進みます。
@MainActor
final class DrivingRouteDetailModelHarness {
    /// テストで使うアカウント識別子です。
    static let account = "account"

    /// ローカルの同期 Repository のフェイクです。
    let syncRepository = ConnectionSessionLocationTrackSyncRepositoryFake()
    /// iCloud の Repository のフェイクです。
    let cloudRepository = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 読み込みを止める門です。
    let gate = DrivingRouteLoadGate()
    /// 読み込みの記録です。
    let recorder = DrivingRouteLoadRecorder()
    /// 検証対象のモデルです。
    private(set) lazy var model = makeModel()

    /// 部品を作ります。
    ///
    /// 責務: フェイク・門・記録を空の状態で用意します(モデルは最初の参照で作ります)。
    init() {}

    /// この端末で記録した軌跡を置きます。
    ///
    /// 責務: 同期記録の無いローカルの軌跡として登録し、通信なしで返る状況を作ります。
    /// - Parameter track: 置く軌跡。
    func addLocalTrack(_ track: ConnectionSessionLocationTrack) {
        syncRepository.addSession(track, accountIdentifier: Self.account)
    }

    /// この端末に行が無いセッションを登録します。
    ///
    /// 責務: 空の軌跡で登録し、iCloud から取得する経路を通る状況を作ります。
    /// - Parameter sessionID: 登録するセッション。
    func registerSessionWithoutLocalTrack(_ sessionID: ConnectionSessionID) {
        syncRepository.addSession(DrivingRouteTestValues.track(sessionID: sessionID), accountIdentifier: Self.account)
    }

    /// iCloud にだけある軌跡を置きます。
    ///
    /// 責務: この端末に行の無いセッションを登録し、他の端末が送った軌跡を iCloud のフェイクへ置きます。
    /// - Parameter track: iCloud に置く軌跡。
    func addCloudOnlyTrack(_ track: ConnectionSessionLocationTrack) {
        registerSessionWithoutLocalTrack(track.sessionID)
        cloudRepository.seedRecord(track, digest: ConnectionSessionLocationTrackTestValues.digest("a"), accountIdentifier: Self.account)
    }

    /// 拒否の後に記録中になり、指定件数の点を取得した軌跡を作ります。
    ///
    /// 責務: 部分の注記が付く軌跡を返します。
    /// - Parameters:
    ///   - sessionID: セッション。
    ///   - sampleCount: 点の数。
    /// - Returns: 軌跡。
    /// - Throws: 値を作れない場合のテスト失敗。
    func partiallyRecordedTrack(sessionID: ConnectionSessionID, sampleCount: Int) throws -> ConnectionSessionLocationTrack {
        DrivingRouteTestValues.track(
            sessionID: sessionID,
            samples: try DrivingRouteTestValues.samples(count: sampleCount),
            eventKinds: [.authorizationDenied, .recording]
        )
    }

    /// 地図の内容が出るまで待ち、その内容を返します。
    ///
    /// 責務: 期限(2秒)内に指定のセッションで `loaded` になるのを待ち、なれなければテストを失敗させます。
    /// - Parameters:
    ///   - sessionID: 待つセッション。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 地図の内容。
    /// - Throws: 期限内に出なければテスト失敗。
    func waitForLoadedContent(
        _ sessionID: ConnectionSessionID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> DrivingRouteMapContent {
        await LocationRecordingBoundedWaiter.waitUntil("loaded", file: file, line: line) {
            self.model.state.sessionID == sessionID && self.loadedContent != nil
        }
        return try XCTUnwrap(loadedContent, file: file, line: line)
    }

    /// 指定の状態になるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に phase が期待値になるのを待ち、なれなければテストを失敗させます。
    /// - Parameters:
    ///   - phase: 期待する状態。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForPhase(_ phase: DrivingRouteDetailPhase, file: StaticString = #filePath, line: UInt = #line) async {
        await LocationRecordingBoundedWaiter.waitUntil("phase \(phase)", file: file, line: line) {
            self.model.state.phase == phase
        }
    }

    /// 読み込みの呼び出しが指定件数になるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に記録の件数が届くのを待ち、届かなければテストを失敗させます。
    /// - Parameters:
    ///   - count: 待つ件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForCallCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await LocationRecordingBoundedWaiter.waitUntil("load calls \(count)", file: file, line: line) {
            self.recorder.calls.count >= count
        }
    }

    /// 門で止まっている読み込みが指定件数になるまで待ちます。
    ///
    /// 責務: 期限(2秒)内に門の待ちが届くのを待ち、届かなければテストを失敗させます。
    /// - Parameters:
    ///   - count: 待つ件数。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    func waitForGateWaiting(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await LocationRecordingBoundedWaiter.waitUntil("gate waiting \(count)", file: file, line: line) {
            self.gate.waitingCount >= count
        }
    }

    /// 門を通った後の再開が記録されるまで待ち、その記録を返します。
    ///
    /// 責務: 期限(2秒)内に指定のセッションの再開が記録されるのを待ち、なければテストを失敗させます。
    /// - Parameters:
    ///   - sessionID: 待つセッション。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: 再開の記録。
    /// - Throws: 期限内に記録されなければテスト失敗。
    func waitForResumption(
        _ sessionID: ConnectionSessionID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> DrivingRouteLoadRecorder.Resumption {
        await LocationRecordingBoundedWaiter.waitUntil("resumption", file: file, line: line) {
            self.recorder.resumptions.contains { $0.sessionID == sessionID }
        }
        return try XCTUnwrap(recorder.resumptions.last { $0.sessionID == sessionID }, file: file, line: line)
    }

    /// 現在の状態が `loaded` なら、その内容です。
    var loadedContent: DrivingRouteMapContent? {
        if case let .loaded(content) = model.state.phase { return content }
        return nil
    }

    /// モデルを作ります。
    ///
    /// 責務: 記録・門・実物のユースケースの順に進む読み込みの closure を渡し、他の部品は既定の実物にします。
    /// - Returns: モデル。
    private func makeModel() -> DrivingRouteDetailModel {
        let useCase = LoadConnectionSessionLocationTrackUseCase(
            syncRepository: syncRepository,
            cloudRepository: cloudRepository
        )
        let recorder = recorder
        let gate = gate
        return DrivingRouteDetailModel(load: { sessionID, accountIdentifier in
            recorder.recordCall(sessionID, accountIdentifier)
            await gate.waitIfHeld(sessionID)
            recorder.recordResumption(sessionID, wasCancelled: Task.isCancelled)
            return try await useCase.execute(sessionID: sessionID, accountIdentifier: accountIdentifier)
        })
    }
}
