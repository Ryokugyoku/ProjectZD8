import Foundation

/// 別Taskで実行した非同期処理の結果を受け取り、終わったかどうかを確かめられる入れ物です。
final class LiveTelemetryAsyncResultBox<Value: Sendable>: @unchecked Sendable {
    /// 結果を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した結果です。
    private var storedValue: Value?
    /// ロックで保護した、結果を受け取ったかどうかです。
    private var storedIsSet = false

    /// 空の入れ物を生成します。
    ///
    /// 責務: 結果を受け取っていない状態を構築します。
    init() {}

    /// 結果を受け取ったかどうかです。
    var isSet: Bool {
        lock.withLock { storedIsSet }
    }

    /// 受け取った結果です。まだ受け取っていなければ `nil` です。
    var value: Value? {
        lock.withLock { storedValue }
    }

    /// 結果を受け取ります。
    ///
    /// 責務: 結果を保存し、受け取り済みにします。
    /// - Parameter value: 受け取る結果。
    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
            storedIsSet = true
        }
    }
}
