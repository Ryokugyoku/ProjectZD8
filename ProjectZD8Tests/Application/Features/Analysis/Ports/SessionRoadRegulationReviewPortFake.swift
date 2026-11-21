import Foundation
@testable import ProjectZD8

/// 交通規制の照合のポートの Fake です。呼び出しを記録し、呼び出しの順番ごとに結果と門を決められます。
///
/// 門(`RoadRegulationTestGate`)で止めた呼び出しは、門が開くまで結果を返しません。
/// `ignoresCancellation` が false なら取消で直ちに `CancellationError` を投げ、true なら取消に応じず門が開いてから結果を返します
/// (取消を受けたことは記録します)。門の待ちには上限(約5秒)があります。
@MainActor
final class SessionRoadRegulationReviewPortFake: SessionRoadRegulationReviewPort {
    /// 1回の呼び出しの振る舞いです。
    struct Response {
        /// 返す結果か投げるエラーです。
        var result: Result<SessionRoadRegulationReviewResult, any Error>
        /// 結果を返す前に待つ門です。nil なら待ちません。
        var gate: RoadRegulationTestGate?
        /// 取消に応じずに門の再開まで待つかです。
        var ignoresCancellation = false
    }

    /// 呼び出しの順に受け取ったセッション ID です。
    private(set) var calls: [ConnectionSessionID] = []
    /// 取消を受けた呼び出しの番号(0 始まり)です。
    private(set) var cancelledCalls: [Int] = []
    /// 結果を返し終えた(または結果のエラーを投げた)呼び出しの番号です。
    private(set) var completedCalls: [Int] = []
    /// 呼び出しの番号ごとの振る舞いです。番号が範囲外なら `fallback` を使います。
    var responses: [Response] = []
    /// 既定の振る舞いです。
    var fallback = Response(result: .success(.noTrack))

    /// Fake を作ります。
    ///
    /// 責務: 呼び出しの記録を空にして用意します。
    init() {}

    /// 責務: 呼び出しを記録し、その番号の振る舞いどおりに門で待ってから結果を返します。
    /// - Parameter sessionID: 対象のセッション。
    /// - Returns: 決めておいた結果。
    /// - Throws: 決めておいたエラー、取消に応じた時の `CancellationError`、門の上限を超えた時の `TimeoutError`。
    func review(sessionID: ConnectionSessionID) async throws -> SessionRoadRegulationReviewResult {
        let index = calls.count
        calls.append(sessionID)
        let response = index < responses.count ? responses[index] : fallback
        do {
            try await wait(for: response)
        } catch is CancellationError {
            cancelledCalls.append(index)
            throw CancellationError()
        }
        if response.ignoresCancellation, Task.isCancelled {
            cancelledCalls.append(index)
        }
        completedCalls.append(index)
        return try response.result.get()
    }

    /// 責務: 門があれば、取消への応じ方に従って門が開くまで待ちます。
    /// - Parameter response: 呼び出しの振る舞い。
    private func wait(for response: Response) async throws {
        guard let gate = response.gate else { return }
        guard response.ignoresCancellation else {
            try await gate.waitAsync()
            return
        }
        try await Task { try await gate.waitAsync() }.value
    }
}
