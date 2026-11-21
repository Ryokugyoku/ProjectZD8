import Foundation

/// 1回の走行の交通規制の照合結果を返すポートです。App 層のアダプターが RoadRegulation の判定で実装します。
@MainActor protocol SessionRoadRegulationReviewPort {
    /// セッションの走行を交通規制データと照合します。
    ///
    /// 責務: 位置と車速を取得済みの交通規制データと照らし合わせ、判定の結果か、照合できない理由を値で返します。
    /// 投げるのは `CancellationError` と保存先のエラーで、握りつぶしません。
    /// - Parameter sessionID: 照合するセッションの ID。
    /// - Returns: 照合の結果。
    func review(sessionID: ConnectionSessionID) async throws -> SessionRoadRegulationReviewResult
}
