import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICURLSessionConfiguration.make()` が、利用者の情報を残さない構成を返すことを検証します。
@MainActor
final class JARTICURLSessionConfigurationTests: XCTestCase {
    /// User-Agent は固定値だけで、版数も端末情報も含みません。
    ///
    /// 責務: 追加ヘッダーが User-Agent の1つだけで、値が `RevTorqueInsight` であることを確認します。
    func testAdditionalHeadersContainOnlyFixedUserAgent() {
        let configuration = JARTICURLSessionConfiguration.make()

        XCTAssertEqual(configuration.httpAdditionalHeaders as? [String: String], ["User-Agent": "RevTorqueInsight"])
    }

    /// クッキーとキャッシュを使いません。
    ///
    /// 責務: クッキーの受け入れ・保存・送信・キャッシュが無効であることを確認します。
    func testCookiesAndCacheAreDisabled() {
        let configuration = JARTICURLSessionConfiguration.make()

        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    /// 時間切れは 30 秒と 900 秒で、バックグラウンド構成ではありません。
    ///
    /// 責務: 2つの時間切れと、識別子を持たない(ephemeral の)構成であることを確認します。
    func testTimeoutsAndEphemeralKind() {
        let configuration = JARTICURLSessionConfiguration.make()

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 900)
        XCTAssertNil(configuration.identifier)
    }
}
