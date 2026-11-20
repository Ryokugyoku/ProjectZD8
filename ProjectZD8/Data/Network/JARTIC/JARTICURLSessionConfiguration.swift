import Foundation

/// JARTIC への通信に使う `URLSessionConfiguration` の作り方です。
nonisolated enum JARTICURLSessionConfiguration {
    /// 通信に付ける User-Agent。版数も端末情報も入れません。
    static let userAgent = "RevTorqueInsight"
    /// 1回の応答待ちの上限(秒)。
    static let requestTimeoutSeconds: TimeInterval = 30
    /// 1回の取得全体の上限(秒)。
    static let resourceTimeoutSeconds: TimeInterval = 900

    /// 利用者の情報を残さない構成を作ります。
    ///
    /// 責務: ephemeral・クッキーなし・キャッシュなし・User-Agent 固定・時間切れ 30/900 秒の構成を返します。
    /// - Returns: バックグラウンド構成ではない `URLSessionConfiguration`。
    static func make() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = resourceTimeoutSeconds
        return configuration
    }
}
