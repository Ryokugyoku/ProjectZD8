import Foundation
import XCTest
@testable import ProjectZD8

/// 取得元のテストが共有する、偽の通信・保存先のフォルダ・検証対象の取得元の組です。
struct JARTICSourceTestEnvironment {
    /// 一覧 JSON の URL(既定と同じ)。
    static let indexURL = URL(string: "https://www.jartic.or.jp/d/opendata/opendata.json")!
    /// 見本の ZIP の URL。
    static let archiveURL = URL(string: "https://www.jartic.or.jp/d/opendata/202611010000/typeD_okinawa.zip")!

    /// ZIP の保存先。テストごとの空のフォルダ(まだ作らない)。
    let directory: URL
    /// 検証対象の取得元。
    let source: URLSessionJARTICRoadRegulationSource
    /// 偽の通信の入れ物。
    let network = JARTICStubbedNetwork.shared

    /// 偽の通信を空にして、取得元を作ります。
    ///
    /// 責務: 既定の構成(User-Agent・クッキーなし)に偽の `URLProtocol` だけを差し込みます。後始末はテストの終了時に登録します。
    @MainActor
    init(testCase: XCTestCase) {
        JARTICStubbedNetwork.shared.reset()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JARTICSourceTests-\(UUID().uuidString)")
        testCase.addTeardownBlock {
            JARTICStubbedNetwork.shared.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let configuration = JARTICURLSessionConfiguration.make()
        configuration.protocolClasses = [JARTICStubbedResponseURLProtocol.self]
        self.directory = directory
        self.source = URLSessionJARTICRoadRegulationSource(downloadDirectory: directory, configuration: configuration)
    }

    /// 見本の ZIP の項目です。
    func entry(url: URL = archiveURL) throws -> RoadRegulationCatalogEntry {
        RoadRegulationCatalogEntry(
            prefecture: try XCTUnwrap(JapanesePrefectureCode(47)), archiveURL: url, publicationStamp: "202611010000"
        )
    }

    /// 保存先のフォルダにあるファイル名の一覧(フォルダが無ければ空)。
    func filesInDirectory() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// 決まった規則で作った本文を返します(位置から値が決まるので期待値を式で書ける)。
    static func body(count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 8) })
    }

    /// 要求に利用者を特定するヘッダーが無く、User-Agent が固定値であることを確認します。
    static func assertMinimalHeaders(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) {
        let headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["User-Agent"], "RevTorqueInsight", file: file, line: line)
        for name in headers.keys.map({ $0.lowercased() }) {
            XCTAssertFalse(["cookie", "authorization", "referer", "origin"].contains(name), name, file: file, line: line)
            XCTAssertFalse(name.hasPrefix("x-"), name, file: file, line: line)
        }
    }
}
