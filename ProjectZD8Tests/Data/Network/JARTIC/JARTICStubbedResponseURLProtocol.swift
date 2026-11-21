import Foundation
@testable import ProjectZD8

/// `JARTICStubbedNetwork` に登録した応答を返す、テスト用の `URLProtocol` です(ネットワークには接続しません)。
nonisolated final class JARTICStubbedResponseURLProtocol: URLProtocol, @unchecked Sendable {
    /// すべての要求を扱います。
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// 要求をそのまま返します。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 登録済みの応答を返します。
    ///
    /// 責務: 要求を記録し、応答の種類に従って本文・エラー・リダイレクトを渡します。登録が無ければ `unsupportedURL` で失敗します。
    override func startLoading() {
        let begun = JARTICStubbedNetwork.shared.begin(request)
        guard let behavior = begun.behavior, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        begun.onStart?(request)
        switch behavior {
        case let .respond(status, body, chunkSize, declaredLength):
            send(url: url, status: status, declaredLength: declaredLength, chunks: Self.split(body, chunkSize))
            client?.urlProtocolDidFinishLoading(self)
        case let .partialThenFail(body, declaredLength, code):
            send(url: url, status: 200, declaredLength: declaredLength, chunks: [body])
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .redirect(target):
            redirect(from: url, to: target)
        case .hold:
            break
        }
    }

    /// 読み込みの中止を知らせます。
    override func stopLoading() {
        JARTICStubbedNetwork.shared.stopNotifier()?()
    }

    /// 応答の頭と本文の塊を渡します。
    private func send(url: URL, status: Int, declaredLength: Int?, chunks: [Data]) {
        var headers: [String: String] = [:]
        if let declaredLength { headers["Content-Length"] = String(declaredLength) }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
    }

    /// 302 のリダイレクトを渡します。
    private func redirect(from url: URL, to target: URL) {
        let headers = ["Location": target.absoluteString]
        guard let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// 本文を指定の大きさに分けます(`nil` や 0 なら1塊)。
    private static func split(_ body: Data, _ size: Int?) -> [Data] {
        guard let size, size > 0, body.count > size else { return [body] }
        return stride(from: 0, to: body.count, by: size).map { body.subdata(in: $0..<min($0 + size, body.count)) }
    }
}
