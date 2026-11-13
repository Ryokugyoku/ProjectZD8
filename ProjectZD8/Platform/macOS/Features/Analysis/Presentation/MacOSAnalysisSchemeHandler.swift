#if os(macOS)
import Foundation
import WebKit

/// 独自スキームの要求へ、同梱のワークベンチと分析データだけを返します。`file://` や外部通信は使いません。
nonisolated struct MacOSAnalysisSchemeHandler: URLSchemeHandler {
    private let content: ResolveAnalysisWebContentUseCase

    /// 責務: 配信内容の解決元を固定します。
    init(content: ResolveAnalysisWebContentUseCase) {
        self.content = content
    }

    /// 責務: 要求URLを内容へ解決し、許可外や不在は404で返します。
    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, Error> {
        AsyncThrowingStream { continuation in
            guard let url = request.url else {
                continuation.finish(throwing: URLError(.badURL))
                return
            }
            guard let resolved = content.content(for: url) else {
                continuation.yield(.response(Self.response(url: url, status: 404, mimeType: "text/plain", length: 0)))
                continuation.finish()
                return
            }
            continuation.yield(.response(Self.response(url: url, status: 200, mimeType: resolved.mimeType, length: resolved.data.count)))
            continuation.yield(.data(resolved.data))
            continuation.finish()
        }
    }

    /// 責務: キャッシュ禁止とコンテンツセキュリティポリシー付きの応答ヘッダーを作ります。
    private static func response(url: URL, status: Int, mimeType: String, length: Int) -> URLResponse {
        let scheme = ResolveAnalysisWebContentUseCase.scheme
        let policy = "default-src 'none'; script-src \(scheme):; style-src \(scheme):; img-src \(scheme): data: blob:; connect-src \(scheme):; base-uri 'none'; form-action 'none'"
        return HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "\(mimeType); charset=utf-8",
                "Content-Length": String(length),
                "Cache-Control": "no-store",
                "Content-Security-Policy": policy,
                "X-Content-Type-Options": "nosniff"
            ]
        )!
    }
}
#endif
