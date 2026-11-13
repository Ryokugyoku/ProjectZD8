import XCTest
@testable import ProjectZD8

/// Webからのメッセージの検証と画面操作への変換を確認します。
final class AnalysisWebMessageTests: XCTestCase {
    /// 責務: 各メッセージ種別が復元できることを確認します。
    func testDecodesKnownTypes() throws {
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "ready"]), .ready)
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "requestSession"]).action, .requestSessionPicker(.addComparison))
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "openSessionPicker"]).action, .requestSessionPicker(.replacePrimary))
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "requestTrend", "includeDemo": true]), .requestTrend(includeDemo: true))
        let id = SessionID()
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "removeSession", "id": id.rawValue.uuidString]), .removeSession(id))
        XCTAssertEqual(try AnalysisWebMessage.decode(["type": "dismissFailure"]).action, .dismissFailure)
        XCTAssertNil(AnalysisWebMessage.ready.action)
    }

    /// 責務: 書き出しは許可したMIMEタイプだけを受け付け、ファイル名を無害化することを確認します。
    func testExportValidation() throws {
        let base64 = Data("a,b".utf8).base64EncodedString()
        let message = try AnalysisWebMessage.decode(["type": "export", "filename": "../evil/x.csv", "mimeType": "text/csv", "base64": base64])
        guard case .export(let request) = message else { return XCTFail("exportのはず") }
        XCTAssertEqual(request.filename, "export.._evil_x.csv")
        XCTAssertFalse(request.filename.contains("/"))
        XCTAssertEqual(request.data, Data("a,b".utf8))
        XCTAssertThrowsError(try AnalysisWebMessage.decode(["type": "export", "filename": "a", "mimeType": "text/html", "base64": base64]))
        XCTAssertThrowsError(try AnalysisWebMessage.decode(["type": "export", "filename": "a", "mimeType": "text/csv", "base64": "***"]))
    }

    /// 責務: 不正な入力を型付きの失敗にすることを確認します。
    func testRejectsMalformed() {
        XCTAssertThrowsError(try AnalysisWebMessage.decode("ready"))
        XCTAssertThrowsError(try AnalysisWebMessage.decode(["foo": 1]))
        XCTAssertThrowsError(try AnalysisWebMessage.decode(["type": "nope"]))
        XCTAssertThrowsError(try AnalysisWebMessage.decode(["type": "removeSession", "id": "x"]))
    }
}
