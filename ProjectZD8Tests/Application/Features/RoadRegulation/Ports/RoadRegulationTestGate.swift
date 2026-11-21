import Foundation

/// 偽物の処理を途中で止めておき、テストから再開させるための門です。待ちには必ず上限があります。
///
/// 止めたテストは、`tearDown` で必ず `open()` して再開させます。
nonisolated final class RoadRegulationTestGate: @unchecked Sendable {
    /// 門の待ちが上限を超えた時に投げるエラーです(止まらない実装を「失敗」にするため)。
    nonisolated struct TimeoutError: Error, Equatable, Sendable {}

    /// 1回の確認の間に待つ時間(ミリ秒)です。
    static let pollMilliseconds = 5
    /// 確認回数の上限です(約5秒)。
    static let maximumPolls = 1_000

    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、開いているかどうかです。
    private var opened: Bool
    /// ロックで保護した、いま待っている数です。
    private var waitingCount = 0

    /// 責務: 開いた状態か閉じた状態の門を作ります。
    /// - Parameter isOpen: 最初から開いているか。
    init(isOpen: Bool = true) {
        opened = isOpen
    }

    /// 責務: 門を閉じ、以後の待ちを止めます。
    func close() {
        lock.withLock { opened = false }
    }

    /// 責務: 門を開き、待っている処理を再開させます。
    func open() {
        lock.withLock { opened = true }
    }

    /// 門が開いているかです。
    var isOpen: Bool {
        lock.withLock { opened }
    }

    /// 門の前で待っている処理があるかです。
    var isWaiting: Bool {
        lock.withLock { waitingCount > 0 }
    }

    /// 責務: 門が開くまで非同期に待ちます。取り消されたら `CancellationError`、上限を超えたら `TimeoutError` を投げます。
    func waitAsync() async throws {
        changeWaiting(by: 1)
        defer { changeWaiting(by: -1) }
        for _ in 0..<Self.maximumPolls {
            if isOpen { return }
            try await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        if isOpen { return }
        throw TimeoutError()
    }

    /// 責務: 門が開くまで同期で待ちます(読み取りのポートは同期のため)。上限を超えたら `TimeoutError` を投げます。
    func waitSync() throws {
        changeWaiting(by: 1)
        defer { changeWaiting(by: -1) }
        for _ in 0..<Self.maximumPolls {
            if isOpen { return }
            usleep(useconds_t(Self.pollMilliseconds * 1_000))
        }
        if isOpen { return }
        throw TimeoutError()
    }

    /// 責務: 待っている数を増減します。
    private func changeWaiting(by delta: Int) {
        lock.withLock { waitingCount += delta }
    }
}
