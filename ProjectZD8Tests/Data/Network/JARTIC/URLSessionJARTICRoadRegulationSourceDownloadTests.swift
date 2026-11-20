import Foundation
import XCTest
@testable import ProjectZD8

/// `URLSessionJARTICRoadRegulationSource.downloadArchive` の保存・進捗・失敗の分類・キャンセル・リダイレクトの制限を、偽の通信で検証します。
@MainActor
final class URLSessionJARTICRoadRegulationSourceDownloadTests: XCTestCase {
    private typealias Environment = JARTICSourceTestEnvironment

    /// 進捗の通知を、通知された順に溜める箱です。
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [RoadRegulationTransferProgress] = []
        var values: [RoadRegulationTransferProgress] { lock.withLock { items } }
        func add(_ value: RoadRegulationTransferProgress) { lock.withLock { items.append(value) } }
    }

    /// ダウンロードを始めて、期限つきで結果を待ちます。
    private func download(_ environment: Environment, url: URL = Environment.archiveURL, log: ProgressLog = ProgressLog()) throws -> TestBoundedAsyncRun<URL> {
        let entry = try environment.entry(url: url)
        let source = environment.source
        return TestBoundedAsyncRun { try await source.downloadArchive(for: entry) { log.add($0) } }
    }

    /// 200 で ZIP が保存され、中身が応答の本文と一致し、進捗が単調に増えて最後が全体の大きさです。
    ///
    /// 責務: 保存先・拡張子・内容・進捗の単調性と終端値・要求のヘッダーを確認します。
    func testSuccessfulDownloadStoresBodyAndReportsMonotonicProgress() async throws {
        let environment = Environment(testCase: self)
        let body = Environment.body(count: 200_000)
        environment.network.stub(Environment.archiveURL, .respond(status: 200, body: body, chunkSize: 50_000, declaredLength: body.count))
        let log = ProgressLog()

        let downloaded = try await download(environment, log: log).value(on: self)
        let file = try XCTUnwrap(downloaded)

        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL.path, environment.directory.standardizedFileURL.path)
        XCTAssertEqual(file.pathExtension, "zip")
        XCTAssertEqual(try Data(contentsOf: file), body)
        let progress = log.values
        XCTAssertFalse(progress.isEmpty)
        XCTAssertEqual(progress, progress.sorted { $0.receivedBytes < $1.receivedBytes })
        XCTAssertEqual(progress.last, RoadRegulationTransferProgress(receivedBytes: Int64(body.count), expectedBytes: Int64(body.count)))
        XCTAssertTrue(progress.allSatisfy { $0.expectedBytes == Int64(body.count) && $0.receivedBytes <= Int64(body.count) })
        let request = try XCTUnwrap(environment.network.requests.first)
        XCTAssertEqual(environment.network.requests.count, 1)
        XCTAssertEqual(request.url, Environment.archiveURL)
        XCTAssertNil(request.url?.query)
        Environment.assertMinimalHeaders(request)
        environment.source.removeDownloadedArchive(at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// 全体の大きさが分からない応答では、進捗の全体の大きさは `nil` です。
    ///
    /// 責務: Content-Length が無い時に、推測の値を入れないことを確認します。
    func testUnknownLengthReportsNilExpectedBytes() async throws {
        let environment = Environment(testCase: self)
        let body = Environment.body(count: 30_000)
        environment.network.stub(Environment.archiveURL, .respond(status: 200, body: body, chunkSize: 10_000, declaredLength: nil))
        let log = ProgressLog()

        let downloaded = try await download(environment, log: log).value(on: self)
        let file = try XCTUnwrap(downloaded)

        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertFalse(log.values.isEmpty)
        XCTAssertTrue(log.values.allSatisfy { $0.expectedBytes == nil })
        XCTAssertEqual(log.values.last?.receivedBytes, Int64(body.count))
    }

    /// HTTP 200 以外と通信の失敗は `downloadFailed` で、ファイルが残りません。
    ///
    /// 責務: 404・500・通信エラー・接続できない・途中で通信が切れた・宣言より短い本文の6通りを確認します。
    func testFailuresAreDownloadFailedAndLeaveNoFile() async throws {
        let body = Environment.body(count: 20_000)
        let behaviors: [JARTICStubbedBehavior] = [
            .respond(status: 404, body: Data("x".utf8), chunkSize: nil, declaredLength: nil),
            .respond(status: 500, body: Data("x".utf8), chunkSize: nil, declaredLength: nil),
            .fail(.timedOut), .fail(.notConnectedToInternet),
            .partialThenFail(body: body.prefix(5_000), declaredLength: body.count, code: .networkConnectionLost),
            .respond(status: 200, body: body.prefix(5_000), chunkSize: nil, declaredLength: body.count)
        ]
        for behavior in behaviors {
            let environment = Environment(testCase: self)
            environment.network.stub(Environment.archiveURL, behavior)

            let error = try await download(environment).failure(on: self)

            XCTAssertEqual(error as? RoadRegulationImportError, .downloadFailed, "\(behavior)")
            XCTAssertEqual(environment.filesInDirectory(), [], "\(behavior)")
        }
    }

    /// 別のホストへのリダイレクトには従わず、`downloadFailed` です。
    ///
    /// 責務: 移動先に要求が届かないことと、ファイルが残らないことを確認します。
    func testRedirectToOtherHostIsRejected() async throws {
        let environment = Environment(testCase: self)
        let other = try XCTUnwrap(URL(string: "https://evil.example/202611010000/typeD_okinawa.zip"))
        environment.network.stub(Environment.archiveURL, .redirect(to: other))
        environment.network.stub(other, .respond(status: 200, body: Environment.body(count: 100), chunkSize: nil, declaredLength: 100))

        let error = try await download(environment).failure(on: self)

        XCTAssertEqual(error as? RoadRegulationImportError, .downloadFailed)
        XCTAssertFalse(environment.network.requests.contains { $0.url == other })
        XCTAssertEqual(environment.filesInDirectory(), [])
    }

    /// https から http へのリダイレクトにも従いません。
    ///
    /// 責務: 同じホストでも https 以外へは移動しないことを確認します。
    func testRedirectToHTTPIsRejected() async throws {
        let environment = Environment(testCase: self)
        let insecure = try XCTUnwrap(URL(string: "http://www.jartic.or.jp/d/opendata/202611010000/typeD_okinawa.zip"))
        environment.network.stub(Environment.archiveURL, .redirect(to: insecure))
        environment.network.stub(insecure, .respond(status: 200, body: Environment.body(count: 100), chunkSize: nil, declaredLength: 100))

        let error = try await download(environment).failure(on: self)

        XCTAssertEqual(error as? RoadRegulationImportError, .downloadFailed)
        XCTAssertFalse(environment.network.requests.contains { $0.url == insecure })
    }

    /// 同じホストの https へのリダイレクトには従います。
    ///
    /// 責務: 許可された移動先の本文が保存されることを確認します。
    func testRedirectToSameHostHTTPSIsFollowed() async throws {
        let environment = Environment(testCase: self)
        let moved = try XCTUnwrap(URL(string: "https://www.jartic.or.jp/d/opendata/202611010000/moved.zip"))
        let body = Environment.body(count: 4_000)
        environment.network.stub(Environment.archiveURL, .redirect(to: moved))
        environment.network.stub(moved, .respond(status: 200, body: body, chunkSize: nil, declaredLength: body.count))

        let file = try await download(environment).value(on: self)

        XCTAssertEqual(try file.map { try Data(contentsOf: $0) }, body)
    }

    /// https 以外の URL は通信せずに `downloadFailed` です。
    ///
    /// 責務: http の項目で要求が1件も出ないことを確認します。
    func testNonHTTPSArchiveURLIsRejectedWithoutRequest() async throws {
        let environment = Environment(testCase: self)
        let insecure = try XCTUnwrap(URL(string: "http://www.jartic.or.jp/d/opendata/202611010000/typeD_okinawa.zip"))
        environment.network.stub(insecure, .respond(status: 200, body: Data([1]), chunkSize: nil, declaredLength: 1))

        let error = try await download(environment, url: insecure).failure(on: self)

        XCTAssertEqual(error as? RoadRegulationImportError, .downloadFailed)
        XCTAssertTrue(environment.network.requests.isEmpty)
    }

    /// ダウンロード中のキャンセルは `CancellationError` で、読み込みが中止されファイルが残りません。
    ///
    /// 責務: 応答が来ないまま取り消し、`downloadFailed` に変換されないことを確認します。
    func testCancellingDownloadThrowsCancellationError() async throws {
        let environment = Environment(testCase: self)
        environment.network.stub(Environment.archiveURL, .hold)
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        environment.network.observe(onStart: { _ in started.fulfill() }, onStop: { stopped.fulfill() })
        let run = try download(environment)
        await fulfillment(of: [started], timeout: 2)

        run.cancel()
        let error = await run.failure(on: self)

        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(environment.filesInDirectory(), [])
    }

    /// 開始前から取り消されている時は、通信せずに `CancellationError` です。
    ///
    /// 責務: 取り消し済みの Task で要求が出ないことを確認します。
    func testAlreadyCancelledDownloadThrowsWithoutRequest() async throws {
        let environment = Environment(testCase: self)
        environment.network.stub(Environment.archiveURL, .respond(status: 200, body: Data([1]), chunkSize: nil, declaredLength: 1))
        let entry = try environment.entry()
        let source = environment.source
        let run = TestBoundedAsyncRun<URL> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.downloadArchive(for: entry) { _ in }
        }

        let error = await run.failure(on: self)

        XCTAssertTrue(error is CancellationError, "\(String(describing: error))")
        XCTAssertTrue(environment.network.requests.isEmpty)
    }
}
