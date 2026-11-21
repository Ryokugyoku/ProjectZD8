import Foundation
@testable import ProjectZD8

/// 偽の通信の設定と、受けた要求の記録を持つ、スレッド安全な入れ物です(1テストごとに `reset()` で空にします)。
nonisolated final class JARTICStubbedNetwork: @unchecked Sendable {
    /// テスト全体で共有する唯一の入れ物。`URLProtocol` が生成を制御できないため static にしています。
    static let shared = JARTICStubbedNetwork()

    private let lock = NSLock()
    private var behaviors: [String: JARTICStubbedBehavior] = [:]
    private var recorded: [URLRequest] = []
    private var startHandler: (@Sendable (URLRequest) -> Void)?
    private var stopHandler: (@Sendable () -> Void)?

    /// 受けた要求を、受けた順に返します。
    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    /// 設定・記録・通知先をすべて消します。
    ///
    /// 責務: 前のテストの状態を持ち越さないようにします。
    func reset() {
        lock.withLock {
            behaviors = [:]
            recorded = []
            startHandler = nil
            stopHandler = nil
        }
    }

    /// URL に対する応答を登録します。
    ///
    /// 責務: 完全一致の URL に応答の種類を結びつけます。
    func stub(_ url: URL, _ behavior: JARTICStubbedBehavior) {
        lock.withLock { behaviors[url.absoluteString] = behavior }
    }

    /// 要求の開始と、読み込みの中止を知らせる先を登録します。
    ///
    /// 責務: キャンセルのテストが、ポーリングなしで開始と中止を待てるようにします。
    func observe(onStart: (@Sendable (URLRequest) -> Void)? = nil, onStop: (@Sendable () -> Void)? = nil) {
        lock.withLock {
            startHandler = onStart
            stopHandler = onStop
        }
    }

    /// 要求を記録し、登録済みの応答と開始の通知先を返します。
    ///
    /// 責務: 要求ごとに1回だけ呼ばれる入口です。
    func begin(_ request: URLRequest) -> (behavior: JARTICStubbedBehavior?, onStart: (@Sendable (URLRequest) -> Void)?) {
        lock.withLock {
            recorded.append(request)
            return (request.url.flatMap { behaviors[$0.absoluteString] }, startHandler)
        }
    }

    /// 読み込みの中止の通知先を返します。
    func stopNotifier() -> (@Sendable () -> Void)? {
        lock.withLock { stopHandler }
    }
}
