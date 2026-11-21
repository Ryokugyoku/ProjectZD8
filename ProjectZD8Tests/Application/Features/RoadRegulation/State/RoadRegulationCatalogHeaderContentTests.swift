import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationCatalogHeaderContent` が、確認の状態ごとにボタンの可否・進行中・状態の文言キー・失敗の印を決めることを検証します。
@MainActor
final class RoadRegulationCatalogHeaderContentTests: XCTestCase {
    private let keys = RoadRegulationSettingsTextKeys()

    /// 全エラーの値です。
    private static let allErrors: [RoadRegulationImportError] = [
        .catalogUnavailable, .catalogFormatChanged, .prefectureNotInCatalog, .downloadFailed, .archiveInvalid,
        .csvFormatChanged, .noRegulationsInArchive, .insufficientStorage, .storageUnavailable,
    ]

    /// ボタンの文言キーは「更新を確認」です。
    ///
    /// 責務: `buttonKey` の値を確認します。
    func testButtonKey() {
        XCTAssertEqual(RoadRegulationCatalogHeaderContent.buttonKey, "road_regulation.data.check_updates")
    }

    /// 未確認は、押せて、進行中でなく、状態の文言も失敗の印も無い。
    ///
    /// 責務: `.notChecked` の内容を確認します。
    func testNotChecked() {
        let content = RoadRegulationCatalogHeaderContent(status: .notChecked, textKeys: keys)

        XCTAssertTrue(content.canCheck)
        XCTAssertFalse(content.isChecking)
        XCTAssertNil(content.statusKey)
        XCTAssertFalse(content.isFailure)
    }

    /// 確認中は、押せず、進行中で、「確認中」の文言を出し、失敗ではない。
    ///
    /// 責務: `.checking` の内容を確認します。
    func testChecking() {
        let content = RoadRegulationCatalogHeaderContent(status: .checking, textKeys: keys)

        XCTAssertFalse(content.canCheck)
        XCTAssertTrue(content.isChecking)
        XCTAssertEqual(content.statusKey, "road_regulation.data.checking")
        XCTAssertFalse(content.isFailure)
    }

    /// 確認済みは、押せて、進行中でなく、「確認済み」の文言を出し、失敗ではない。
    ///
    /// 責務: `.checked` の内容を確認します。
    func testChecked() {
        let catalog = RoadRegulationTestValues.catalog([RoadRegulationTestValues.prefecture(13)])
        let content = RoadRegulationCatalogHeaderContent(
            status: .checked(at: RoadRegulationTestValues.fixedNow, catalog: catalog), textKeys: keys
        )

        XCTAssertTrue(content.canCheck)
        XCTAssertFalse(content.isChecking)
        XCTAssertEqual(content.statusKey, "road_regulation.data.checked")
        XCTAssertFalse(content.isFailure)
    }

    /// 失敗は、全エラーで、押せて、進行中でなく、そのエラーの文言キーを出し、失敗の印が付く。
    ///
    /// 責務: `.failed` の内容を全エラーで確認します。
    func testFailedForEveryError() {
        for error in Self.allErrors {
            let content = RoadRegulationCatalogHeaderContent(status: .failed(error), textKeys: keys)
            let key = content.statusKey ?? ""

            XCTAssertTrue(content.canCheck, "\(error)")
            XCTAssertFalse(content.isChecking, "\(error)")
            XCTAssertTrue(key.hasPrefix("road_regulation.error."), "\(error): \(key)")
            XCTAssertEqual(key, keys.errorKey(for: error), "\(error)")
            XCTAssertTrue(content.isFailure, "\(error)")
        }
    }

    /// 失敗のキーはエラーごとに異なります。
    ///
    /// 責務: エラー違いが同じ文言に潰れないことを確認します。
    func testFailedKeysAreDistinct() {
        let all = Self.allErrors.compactMap { RoadRegulationCatalogHeaderContent(status: .failed($0), textKeys: keys).statusKey }

        XCTAssertEqual(Set(all).count, Self.allErrors.count)
    }

    /// 既定の文言キーの選択器でも同じ内容になります。
    ///
    /// 責務: `textKeys` の既定値を確認します。
    func testDefaultTextKeys() {
        XCTAssertEqual(
            RoadRegulationCatalogHeaderContent(status: .checking),
            RoadRegulationCatalogHeaderContent(status: .checking, textKeys: keys)
        )
    }
}
