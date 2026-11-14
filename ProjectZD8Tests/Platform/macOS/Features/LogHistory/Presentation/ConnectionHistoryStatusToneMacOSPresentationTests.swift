#if os(macOS)
import SwiftUI
import XCTest
@testable import ProjectZD8

/// 共通の状態トーンからmacOS表示色への対応を検証します。
@MainActor
final class ConnectionHistoryStatusToneMacOSPresentationTests: XCTestCase {
    /// 各トーンは分割前の画面と同じ色になります。
    ///
    /// 責務: neutral / caution / positive / critical / informative の全分岐を確認します。
    func testEachToneMapsToPreviousColor() {
        XCTAssertEqual(ConnectionHistoryStatusTone.neutral.color, .secondary)
        XCTAssertEqual(ConnectionHistoryStatusTone.caution.color, .orange)
        XCTAssertEqual(ConnectionHistoryStatusTone.positive.color, .green)
        XCTAssertEqual(ConnectionHistoryStatusTone.critical.color, .red)
        XCTAssertEqual(ConnectionHistoryStatusTone.informative.color, .blue)
    }

    /// Raw状態バッジの色は分割前の画面の三項演算・分岐と一致します。
    ///
    /// 責務: iCloud状態とローカル状態の全ケースで、バッジのトーン経由の色を確認します。
    func testRawStatusBadgeColorsMatchPreviousView() {
        let cloudStates: [ConnectionSessionCloudSyncState] = [.notUploaded, .pending, .uploaded, .failed]
        let localStates: [ConnectionSessionLocalRawState] = [.empty, .available, .removed]
        let cloudColors = cloudStates.map { ConnectionHistoryRawStatusBadge(cloudState: $0).tone.color }
        let expectedCloud: [Color] = cloudStates.map {
            switch $0 {
            case .notUploaded: .secondary
            case .pending: .orange
            case .uploaded: .green
            case .failed: .red
            }
        }
        XCTAssertEqual(cloudColors, expectedCloud)

        let localColors = localStates.map { ConnectionHistoryRawStatusBadge(localState: $0).tone.color }
        let expectedLocal: [Color] = localStates.map { $0 == .available ? .blue : .secondary }
        XCTAssertEqual(localColors, expectedLocal)
    }
}
#endif
