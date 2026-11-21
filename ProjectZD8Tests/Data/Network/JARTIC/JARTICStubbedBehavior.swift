import Foundation
@testable import ProjectZD8

/// `JARTICStubbedResponseURLProtocol` が1つの URL に対して返す、用意した応答の種類です。
nonisolated enum JARTICStubbedBehavior: Sendable {
    /// 状態コードと本文を返して終わる。`chunkSize` ごとに分けて渡し、`declaredLength` を Content-Length に宣言する(`nil` なら宣言しない)。
    case respond(status: Int, body: Data, chunkSize: Int?, declaredLength: Int?)
    /// 状態 200 と本文の一部を渡した後、通信エラーで切れる。
    case partialThenFail(body: Data, declaredLength: Int, code: URLError.Code)
    /// 応答を返さず通信エラーにする。
    case fail(URLError.Code)
    /// 別の URL への 302 のリダイレクトを返す。
    case redirect(to: URL)
    /// 何も返さず、読み込みの中止(`stopLoading`)まで待つ。
    case hold
}
