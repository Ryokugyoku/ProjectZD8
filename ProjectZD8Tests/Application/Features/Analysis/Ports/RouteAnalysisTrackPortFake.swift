import Foundation
@testable import ProjectZD8

/// 解析の走行ルートの読み込みポートの Fake です。セッションごとに返す結果を置き、呼び出しと完了を記録します。
///
/// 読み込みは門(`DrivingRouteLoadGate`)で止められ、**取り消しに応じません**(止めた読み込みは、取り消されても再開まで待ち、
/// 置いた結果を返します)。古い結果を捨てる仕組みを、取り消しに頼らずに確かめるためです。止めたまま終わらないよう、
/// テストの tearDown で `gate.releaseAll()` を必ず呼びます。
@MainActor
final class RouteAnalysisTrackPortFake: RouteAnalysisTrackPort {
    /// 読み込みの呼び出しの記録です。
    struct Call: Equatable {
        /// 読み込んだセッションです。
        let sessionID: ConnectionSessionID
        /// 渡されたアカウント識別子です。
        let accountIdentifier: String
    }

    /// 読み込みの完了(結果を返す直前)の記録です。
    struct Completion: Equatable {
        /// 読み込んだセッションです。
        let sessionID: ConnectionSessionID
        /// 結果を返す時点で、呼び出し元のタスクが取り消されていたかです。
        let wasCancelled: Bool
    }

    /// 結果を置いていないセッションで返す失敗です。
    static let unconfiguredResult = RouteAnalysisTrackLoadResult.failed(messageKey: "test.unconfigured", isRetryable: false)

    /// 読み込みを止める門です。
    let gate = DrivingRouteLoadGate()
    /// セッションごとに返す結果です。
    var results: [ConnectionSessionID: RouteAnalysisTrackLoadResult] = [:]
    /// セッションごとに投げる失敗です(契約外の失敗に対するモデルの扱いを確かめるために使います)。結果より優先します。
    var errors: [ConnectionSessionID: any Error] = [:]
    /// 呼ばれた順の呼び出しです。
    private(set) var calls: [Call] = []
    /// 完了した順の記録です。
    private(set) var completions: [Completion] = []

    /// 結果を置いていない Fake を作ります。
    ///
    /// 責務: 結果も記録も無い状態を作ります。
    init() {}

    /// 走行ルートを読み込みます。
    ///
    /// 責務: 呼び出しを記録し、門で止める対象なら再開まで待ち(取り消しには応じない)、完了を記録して、置いた失敗を投げるか置いた結果を返します。
    /// - Parameters:
    ///   - sessionID: 読み込むセッション。
    ///   - accountIdentifier: アカウント識別子。
    /// - Returns: 置いた結果。無ければ `unconfiguredResult`。
    /// - Throws: 置いた失敗。
    func loadRoute(sessionID: ConnectionSessionID, accountIdentifier: String) async throws -> RouteAnalysisTrackLoadResult {
        calls.append(Call(sessionID: sessionID, accountIdentifier: accountIdentifier))
        await gate.waitIfHeld(sessionID)
        completions.append(Completion(sessionID: sessionID, wasCancelled: Task.isCancelled))
        if let error = errors[sessionID] {
            throw error
        }
        return results[sessionID] ?? Self.unconfiguredResult
    }
}
