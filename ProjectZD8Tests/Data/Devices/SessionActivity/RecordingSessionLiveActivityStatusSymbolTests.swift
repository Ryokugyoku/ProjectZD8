import XCTest
@testable import ProjectZD8

/// `RecordingSessionLiveActivityStatusSymbol` のアイコン名を検証します。
///
/// 仕様: U5 受け入れ条件 10・13(B14。表示は変えない)。
final class RecordingSessionLiveActivityStatusSymbolTests: XCTestCase {
    /// 強調ごとのアイコン名は、通常が記録中の丸、警告が注意の三角です。
    ///
    /// 責務: `name(for:)` の2分岐を確認します。
    func testNameForTone() {
        XCTAssertEqual(RecordingSessionLiveActivityStatusSymbol.name(for: .normal), "record.circle")
        XCTAssertEqual(RecordingSessionLiveActivityStatusSymbol.name(for: .warning), "exclamationmark.triangle.fill")
    }

    /// [切断]ボタンと写真のプレースホルダーのアイコン名は固定です。
    ///
    /// 責務: 2つの定数を確認します。
    func testFixedSymbolNames() {
        XCTAssertEqual(RecordingSessionLiveActivityStatusSymbol.stopActionName, "stop.circle.fill")
        XCTAssertEqual(RecordingSessionLiveActivityStatusSymbol.photoPlaceholderName, "car.fill")
    }
}
