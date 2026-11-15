import XCTest

/// 非同期ポートの fake が返す結果を、事前に積んだ台本か、テストが後から渡す結果で決める仕組みです。
///
/// 台本が空の時の呼び出しは保留され、テストが `resumeOldest` で結果を渡すまで戻りません。
/// 保留したまま終えないよう、テストの終了時に `failAllPending()` で全ての保留を `CancellationError` で終わらせます。
@MainActor
final class AdapterLinkSupervisionScriptedResponses<Value: Sendable> {
    /// 呼び出された回数です。
    private(set) var callCount = 0

    /// 次の呼び出しから順に返す台本です。
    private var scripted: [Result<Value, any Error>] = []

    /// 結果を待っている呼び出しです。古い順に並びます。
    private var pending: [CheckedContinuation<Value, any Error>] = []

    /// 結果を待っている呼び出しの件数です。
    var pendingCount: Int { pending.count }

    /// 次の呼び出しで返す結果を台本の末尾へ積みます。
    ///
    /// 責務: 1件の結果を保留せずに返す台本へ追加します。
    /// - Parameter result: 返す値か投げるエラー。
    func enqueue(_ result: Result<Value, any Error>) {
        scripted.append(result)
    }

    /// 1回の呼び出しに結果を返します。
    ///
    /// 責務: 台本があれば先頭を返し、なければテストから結果が渡されるまで保留します。
    /// - Returns: 台本またはテストが渡した値。
    /// - Throws: 台本またはテストが渡したエラー。
    func next() async throws -> Value {
        callCount += 1
        if !scripted.isEmpty {
            return try scripted.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    /// 最も古い保留中の呼び出しへ結果を渡します。
    ///
    /// 責務: 保留が1件もなければテストを失敗させ、あれば古い順に1件だけ再開します。
    /// - Parameter result: 渡す値かエラー。
    func resumeOldest(with result: Result<Value, any Error>, file: StaticString = #filePath, line: UInt = #line) {
        guard !pending.isEmpty else {
            XCTFail("保留中の呼び出しがありません", file: file, line: line)
            return
        }
        pending.removeFirst().resume(with: result)
    }

    /// 全ての保留中の呼び出しを `CancellationError` で終わらせます。
    ///
    /// 責務: テスト終了後に再開されない継続を残さないようにします。
    func failAllPending() {
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }
}
