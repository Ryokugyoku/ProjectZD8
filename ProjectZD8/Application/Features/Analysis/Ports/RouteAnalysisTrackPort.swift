/// 解析が走行ルートを読み込むためのポートです。App 層のアダプターが LogHistory の処理で実装します。
@MainActor protocol RouteAnalysisTrackPort {
    /// セッションの走行ルートを読み込みます。
    ///
    /// 責務: 軌跡を読み、区切った走行ルートか、描けない理由か、失敗を値で返します。投げるのは `CancellationError` だけです。
    /// - Parameters:
    ///   - sessionID: 読み込むセッションの ID。
    ///   - accountIdentifier: サインイン中のアカウントの識別子。
    /// - Returns: 読み込みの結果。
    func loadRoute(sessionID: ConnectionSessionID, accountIdentifier: String) async throws -> RouteAnalysisTrackLoadResult
}
