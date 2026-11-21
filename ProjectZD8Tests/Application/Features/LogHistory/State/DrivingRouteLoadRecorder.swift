import Foundation
@testable import ProjectZD8

/// 走行ルートのモデルが呼んだ読み込みを、開始と再開(取消の有無)に分けて記録します。
@MainActor
final class DrivingRouteLoadRecorder {
    /// 読み込みの呼び出しです。
    struct Call: Equatable {
        /// 読み込むセッションです。
        let sessionID: ConnectionSessionID
        /// 読み込みに使うアカウント識別子です。
        let accountIdentifier: String
    }

    /// 門を通った後の再開です。
    struct Resumption: Equatable {
        /// 再開したセッションです。
        let sessionID: ConnectionSessionID
        /// 再開した時点で読み込みのタスクが取り消されていたかです。
        let wasCancelled: Bool
    }

    /// 呼ばれた順の読み込みです。
    private(set) var calls: [Call] = []
    /// 再開した順の記録です。
    private(set) var resumptions: [Resumption] = []

    /// 空の記録を作ります。
    ///
    /// 責務: 呼び出しも再開も無い状態を作ります。
    init() {}

    /// 読み込みの開始を記録します。
    ///
    /// 責務: セッションとアカウントを呼ばれた順に残します。
    /// - Parameters:
    ///   - sessionID: 読み込むセッション。
    ///   - accountIdentifier: アカウント識別子。
    func recordCall(_ sessionID: ConnectionSessionID, _ accountIdentifier: String) {
        calls.append(Call(sessionID: sessionID, accountIdentifier: accountIdentifier))
    }

    /// 門を通った後の再開を記録します。
    ///
    /// 責務: 再開の時点の取消の有無を残します。
    /// - Parameters:
    ///   - sessionID: 再開したセッション。
    ///   - wasCancelled: 取り消されていたか。
    func recordResumption(_ sessionID: ConnectionSessionID, wasCancelled: Bool) {
        resumptions.append(Resumption(sessionID: sessionID, wasCancelled: wasCancelled))
    }
}
