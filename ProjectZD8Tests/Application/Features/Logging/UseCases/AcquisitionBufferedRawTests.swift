import Foundation
import XCTest
@testable import ProjectZD8

/// 保存待ちのRawを、連番付きのRaw entryへ変換することを検証します。
final class AcquisitionBufferedRawTests: XCTestCase {
    /// 連番以外の全項目をそのまま写し、指定した連番を付けます。
    ///
    /// 責務: 実時刻・経過・Service/PID・payload・単調時刻・区間番号の対応を確認します。
    func testEntryCopiesAllFieldsWithSequence() {
        let raw = AcquisitionBufferedRaw(
            observedAt: Date(timeIntervalSince1970: 33), monotonicNanoseconds: 777, segmentOrdinal: 4,
            elapsedNanoseconds: 55, request: OBDPIDRequest(service: 0x01, pid: 0x0D), payload: [0x12, 0x34]
        )

        XCTAssertEqual(raw.entry(sequence: 91), ConnectionSessionRawLogEntry(
            sequence: 91, observedAt: Date(timeIntervalSince1970: 33), batchElapsedNanoseconds: 55,
            service: 0x01, pid: 0x0D, payload: [0x12, 0x34], monotonicNanoseconds: 777, segmentOrdinal: 4
        ))
    }
}
