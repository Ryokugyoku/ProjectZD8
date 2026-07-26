#if os(iOS)
import Foundation
import XCTest
@testable import ProjectZD8

/// ExternalAccessoryストリームのMain RunLoop開閉規則を検証します。
@MainActor
final class IOSExternalAccessoryStreamLifecycleTests: XCTestCase {
    /// 入出力を開いて閉じる対称なライフサイクルを検証します。
    ///
    /// 責務: Main RunLoop用ライフサイクルが1組のFoundationストリームを開通後に閉鎖できることを確認します。
    func testOpenAndCloseStreamsSymmetrically() {
        let inputStream = InputStream(data: Data([0x3E]))
        let outputStream = OutputStream.toMemory()
        let lifecycle = IOSExternalAccessoryStreamLifecycle()

        lifecycle.open(inputStream: inputStream, outputStream: outputStream)

        XCTAssertNotEqual(inputStream.streamStatus, .notOpen)
        XCTAssertNotEqual(outputStream.streamStatus, .notOpen)

        lifecycle.close(inputStream: inputStream, outputStream: outputStream)

        XCTAssertEqual(inputStream.streamStatus, .closed)
        XCTAssertEqual(outputStream.streamStatus, .closed)
    }
}
#endif
