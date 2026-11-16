import Foundation
import XCTest
@testable import ProjectZD8

/// 設定画面の注目要求を、未消費でまだ処理していない番号の時だけ強調表示することを検証します。
@MainActor
final class AdapterSettingsAttentionPolicyTests: XCTestCase {
    /// 判定対象です。
    private let policy = AdapterSettingsAttentionPolicy()

    /// 未消費で、まだ処理していない番号なら強調表示します。
    ///
    /// 責務: 表示する唯一の組み合わせを確認します。
    func testPendingUnhandledSequencePresents() {
        XCTAssertTrue(policy.shouldPresent(sequence: 2, isPending: true, handledSequence: 1))
        XCTAssertTrue(policy.shouldPresent(sequence: 1, isPending: true, handledSequence: 0))
    }

    /// 未消費でも、その番号を処理済みなら強調表示しません。
    ///
    /// 責務: 同じ要求を2回強調しないことを確認します。
    func testPendingHandledSequenceDoesNotPresent() {
        XCTAssertFalse(policy.shouldPresent(sequence: 3, isPending: true, handledSequence: 3))
    }

    /// 消費済みなら、番号によらず強調表示しません。
    ///
    /// 責務: 通常の手動遷移で強調しないことを確認します。
    func testConsumedRequestDoesNotPresent() {
        XCTAssertFalse(policy.shouldPresent(sequence: 2, isPending: false, handledSequence: 1))
        XCTAssertFalse(policy.shouldPresent(sequence: 2, isPending: false, handledSequence: 2))
    }

    /// 番号の境界(0 と 0、最大値、処理済み番号より小さい番号)で、番号の一致だけを処理済みとみなします。
    ///
    /// 責務: 0・最大値・大小関係の境界で判定が番号の一致に従うことを確認します。
    func testSequenceBoundaries() {
        XCTAssertFalse(policy.shouldPresent(sequence: 0, isPending: true, handledSequence: 0))
        XCTAssertTrue(policy.shouldPresent(sequence: 0, isPending: true, handledSequence: 1))
        XCTAssertFalse(policy.shouldPresent(sequence: .max, isPending: true, handledSequence: .max))
        XCTAssertTrue(policy.shouldPresent(sequence: .max, isPending: true, handledSequence: .max - 1))
        XCTAssertFalse(policy.shouldPresent(sequence: 0, isPending: false, handledSequence: 0))
    }
}
