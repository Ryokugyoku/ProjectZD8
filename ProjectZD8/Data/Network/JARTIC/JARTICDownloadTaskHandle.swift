import Foundation

/// 進行中のダウンロードのタスクとセッションを持ち、キャンセルと後片付けを受け持つ入れ物です。
nonisolated final class JARTICDownloadTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var session: URLSession?
    private var isCancelled = false

    /// タスクとセッションを登録します。
    ///
    /// 責務: 登録前にキャンセルされていれば、すぐタスクを取り消します。
    func register(task: URLSessionTask, session: URLSession) {
        lock.lock()
        self.task = task
        self.session = session
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { task.cancel() }
    }

    /// ダウンロードを取り消します。
    ///
    /// 責務: 登録済みのタスクを取り消し、未登録なら登録時に取り消すよう印を残します。
    func cancel() {
        lock.lock()
        isCancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }

    /// セッションを無効にします。
    ///
    /// 責務: 完了後にセッションと delegate の参照を解放させます。
    func invalidate() {
        lock.lock()
        let current = session
        session = nil
        task = nil
        lock.unlock()
        current?.finishTasksAndInvalidate()
    }
}
