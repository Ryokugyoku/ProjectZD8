import Foundation
import XCTest
@testable import ProjectZD8

/// `URLSessionJARTICRoadRegulationSource` の一覧の取得と、ダウンロードした ZIP の掃除を、偽の通信で検証します。
@MainActor
final class URLSessionJARTICRoadRegulationSourceTests: XCTestCase {
    private typealias Environment = JARTICSourceTestEnvironment

    /// 一覧を取得して解読し、要求に Cookie や余計なヘッダー・クエリが付きません。
    ///
    /// 責務: 47件の取得と、要求の URL・メソッド・User-Agent・ヘッダーを確認します。
    func testCatalogIsFetchedWithMinimalRequest() async throws {
        let environment = Environment(testCase: self)
        let index = JARTICIndexJSONBuilder.realisticIndex()
        environment.network.stub(Environment.indexURL, .respond(status: 200, body: index, chunkSize: nil, declaredLength: nil))
        let source = environment.source

        let run = TestBoundedAsyncRun { try await source.currentCatalog() }
        let catalog = await run.value(on: self)

        XCTAssertEqual(catalog?.entries.count, 47)
        XCTAssertEqual(catalog?.dataMonth, RoadRegulationDataMonth(year: 2026, month: 9))
        let requests = environment.network.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, Environment.indexURL)
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        Environment.assertMinimalHeaders(request)
    }

    /// 一覧の取得の失敗は `catalogUnavailable` です。
    ///
    /// 責務: 404・500・通信エラー・接続できない場合が、すべて通信失敗に分類されることを確認します。
    func testCatalogTransportFailuresAreCatalogUnavailable() async throws {
        let behaviors: [JARTICStubbedBehavior] = [
            .respond(status: 404, body: Data(), chunkSize: nil, declaredLength: nil),
            .respond(status: 500, body: Data("error".utf8), chunkSize: nil, declaredLength: nil),
            .fail(.notConnectedToInternet), .fail(.timedOut), .fail(.networkConnectionLost)
        ]
        for behavior in behaviors {
            let environment = Environment(testCase: self)
            environment.network.stub(Environment.indexURL, behavior)
            let source = environment.source

            let error = await TestBoundedAsyncRun { try await source.currentCatalog() }.failure(on: self)

            XCTAssertEqual(error as? RoadRegulationImportError, .catalogUnavailable, "\(behavior)")
        }
    }

    /// 200 でも中身が想定と違えば `catalogFormatChanged` です。
    ///
    /// 責務: 読めない本文と、typeD の無い一覧が、通信失敗ではなく形式の変化になることを確認します。
    func testUnreadableOrTypeDLessIndexIsFormatChanged() async throws {
        let noTypeD = JARTICIndexJSONBuilder.data([JARTICIndexJSONBuilder.section(type: "typeB", rows: JARTICIndexJSONBuilder.fullRows())])
        for body in [Data("<html></html>".utf8), noTypeD] {
            let environment = Environment(testCase: self)
            environment.network.stub(Environment.indexURL, .respond(status: 200, body: body, chunkSize: nil, declaredLength: nil))
            let source = environment.source

            let error = await TestBoundedAsyncRun { try await source.currentCatalog() }.failure(on: self)

            XCTAssertEqual(error as? RoadRegulationImportError, .catalogFormatChanged)
        }
    }

    /// 一覧の取得中にキャンセルすると `CancellationError` です。
    ///
    /// 責務: 応答が来ないまま取り消し、通信エラーに変換されず、読み込みが中止されることを確認します。
    func testCancellingCatalogFetchThrowsCancellationError() async throws {
        let environment = Environment(testCase: self)
        environment.network.stub(Environment.indexURL, .hold)
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        environment.network.observe(onStart: { _ in started.fulfill() }, onStop: { stopped.fulfill() })
        let source = environment.source
        let run = TestBoundedAsyncRun { try await source.currentCatalog() }
        await fulfillment(of: [started], timeout: 2)

        run.cancel()
        let error = await run.failure(on: self)

        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
        await fulfillment(of: [stopped], timeout: 2)
    }

    /// `removeDownloadedArchive` は保存先のファイルだけを消します。
    ///
    /// 責務: 保存先のファイルが消え、保存先の外のファイルと、存在しないファイルへの呼び出しは安全であることを確認します。
    func testRemoveDownloadedArchiveRemovesOnlyFilesInDownloadDirectory() throws {
        let environment = Environment(testCase: self)
        try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        let inside = environment.directory.appendingPathComponent("a.zip")
        let outsideDirectory = environment.directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: outsideDirectory) }
        let outside = outsideDirectory.appendingPathComponent("b.zip")
        try Data([1]).write(to: inside)
        try Data([2]).write(to: outside)

        environment.source.removeDownloadedArchive(at: inside)
        environment.source.removeDownloadedArchive(at: inside)
        environment.source.removeDownloadedArchive(at: outside)

        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    /// `removeLeftoverDownloads` は保存先の中身をすべて消し、フォルダが無くても安全です。
    ///
    /// 責務: 残った複数のファイルが消えることと、保存先が無い場合に何も起きないことを確認します。
    func testRemoveLeftoverDownloadsClearsDirectoryAndToleratesMissingDirectory() throws {
        let environment = Environment(testCase: self)
        environment.source.removeLeftoverDownloads()
        try FileManager.default.createDirectory(at: environment.directory, withIntermediateDirectories: true)
        for name in ["x.zip", "y.zip"] {
            try Data([1]).write(to: environment.directory.appendingPathComponent(name))
        }

        environment.source.removeLeftoverDownloads()

        XCTAssertEqual(environment.filesInDirectory(), [])
    }
}
