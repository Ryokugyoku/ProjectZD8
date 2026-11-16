import Foundation
@testable import ProjectZD8

/// 認証モデルテストで端末間セッション失効操作を記録します。
@MainActor
final class AuthenticationModelSessionRevocationPortFake: AccountSessionRevocationPort {
    /// 現在世代の受理を要求されたユーザー識別子です。
    private(set) var registeredIdentifiers: [String] = []

    /// 失効発行を要求されたユーザー識別子です。
    private(set) var publishedIdentifiers: [String] = []

    /// 現在監視中のユーザー識別子です。
    private(set) var observedIdentifier: String?

    /// 監視終了を要求された回数です。
    private(set) var stopCount = 0

    /// テストから実行する現在の失効通知処理です。
    private var receiveRevocation: (() -> Void)?

    /// 現在世代の受理要求を記録します。
    ///
    /// 責務: 1件のセッション基準登録をテストから検証可能な履歴へ追加します。
    /// - Parameter userIdentifier: 登録を要求されたユーザー識別子。
    func registerCurrentSession(for userIdentifier: String) {
        registeredIdentifiers.append(userIdentifier)
    }

    /// 新しい失効世代の発行要求を記録します。
    ///
    /// 責務: 1件の失効発行をテストから検証可能な履歴へ追加します。
    /// - Parameter userIdentifier: 発行を要求されたユーザー識別子。
    func publishRevocation(for userIdentifier: String) {
        publishedIdentifiers.append(userIdentifier)
    }

    /// 失効監視対象とコールバックを保持します。
    ///
    /// 責務: 1件の失効監視要求をテストから起動可能なコールバックへ保存します。
    /// - Parameters:
    ///   - userIdentifier: 監視を要求されたユーザー識別子。
    ///   - receive: テストが失効を模擬するときに実行する処理。
    func startObserving(
        for userIdentifier: String,
        receive: @escaping () -> Void
    ) {
        observedIdentifier = userIdentifier
        receiveRevocation = receive
    }

    /// 失効監視の終了要求を記録します。
    ///
    /// 責務: 現在のFake監視状態を未購読へ戻して終了回数を加算します。
    func stopObserving() {
        stopCount += 1
        observedIdentifier = nil
        receiveRevocation = nil
    }

    /// 保存済み失効コールバックをテストから実行します。
    ///
    /// 責務: 他端末からの失効受信を1回のFakeコールバック実行として再現します。
    func deliverRevocation() {
        receiveRevocation?()
    }
}
