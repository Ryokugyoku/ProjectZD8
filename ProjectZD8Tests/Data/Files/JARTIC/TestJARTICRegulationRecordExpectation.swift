import Foundation
import XCTest
@testable import ProjectZD8

/// 行の解釈の結果(`RoadRegulationArchiveRecord`)を、期待どおりの形かどうか検証する補助です。
nonisolated enum TestJARTICRegulationRecordExpectation {
    /// 責務: 結果が規制として採用されていれば下書きを返し、そうでなければテストを失敗させます。
    static func draft(_ record: RoadRegulationArchiveRecord, file: StaticString = #filePath, line: UInt = #line) throws -> RoadRegulationDraft {
        guard case .regulation(let draft) = record else {
            XCTFail("規制として採用されるはずが \(record) でした", file: file, line: line)
            throw ExpectationError.notRegulation
        }
        return draft
    }

    /// 責務: 結果が指定の破棄の理由であることを検証します。
    static func assertRejected(
        _ record: RoadRegulationArchiveRecord,
        _ reason: RoadRegulationRowRejection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(record, .rejected(reason), file: file, line: line)
    }

    /// 責務: 結果が指定の読み飛ばしの理由であることを検証します。
    static func assertSkipped(
        _ record: RoadRegulationArchiveRecord,
        _ reason: RoadRegulationRowSkipReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(record, .skipped(reason), file: file, line: line)
    }

    private enum ExpectationError: Error {
        case notRegulation
    }
}
