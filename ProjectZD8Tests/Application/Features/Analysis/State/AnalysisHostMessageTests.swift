import XCTest
@testable import ProjectZD8

/// ネイティブからWebへ送る設定メッセージの写し方を検証します。
final class AnalysisHostMessageTests: XCTestCase {
    /// 責務: 読み込み段階・進捗・失敗種別・セッションのパス・長期傾向のパスが状態から写されることを確認します。
    func testMapsState() throws {
        var state = AnalysisState(languageCode: "es")
        let sessionID = SessionID()
        let vehicleID = VehicleID()
        state.loadedSessions = [AnalysisLoadedSession(id: sessionID, datasetPath: AnalysisDatasetStore.datasetPath(for: sessionID), vehicleName: "V", startedAt: Date(), isDemo: false)]
        state.trend = .ready(vehicleID)

        state.phase = .downloading(sessionID, progress: 0.4)
        var message = AnalysisHostMessage(state: state)
        XCTAssertEqual(message.language, "es")
        XCTAssertEqual(message.phase, "downloading")
        XCTAssertEqual(message.progress, 0.4)
        XCTAssertEqual(message.trendPath, "trend/\(vehicleID.rawValue.uuidString).json")
        XCTAssertEqual(message.sessions.map(\.id), [sessionID.rawValue.uuidString])

        state.phase = .failed(.downloadFailed(.network))
        message = AnalysisHostMessage(state: state)
        XCTAssertEqual(message.phase, "failed")
        XCTAssertEqual(message.failure, "downloadFailed")
        XCTAssertNil(message.progress)

        state.phase = .awaitingDownloadConsent(sessionID)
        XCTAssertEqual(AnalysisHostMessage(state: state).phase, "idle", "確認待ちはネイティブのダイアログが担当する")
    }

    /// 責務: JSON文字列がWeb側の読む項目名を持つことを確認します。
    func testJSONKeys() throws {
        let json = try AnalysisHostMessage(state: AnalysisState(languageCode: "ja")).jsonString()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "configure")
        for key in ["language", "sessions", "phase"] { XCTAssertNotNil(object[key], key) }
    }
}
