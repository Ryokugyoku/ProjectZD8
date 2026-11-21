import XCTest
@testable import ProjectZD8

/// `RoadRegulationStatusConfirmation` の、連続回数による切り替えと数え直しを検証します。
final class RoadRegulationStatusConfirmationTests: XCTestCase {
    private typealias Confirmation = RoadRegulationStatusConfirmation<String>

    /// 責務: 連番を時刻(秒)に一致させた印を作ります。
    private func mark(_ sequence: Int64) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: Double(sequence), sequence: sequence, observedAt: Date(timeIntervalSince1970: Double(sequence)))
    }

    /// 責務: 初期状態が現在の状態になり、同じ値が来ても変化しないことを確かめます。
    func testSameStatusDoesNotChange() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertEqual(confirmation.current, "A")
        XCTAssertNil(confirmation.observe("A", at: mark(1), requiredCount: 3))
        XCTAssertEqual(confirmation.current, "A")
    }

    /// 責務: 必要な回数だけ続いた時に切り替わり、切り替えの時刻が連続の最初の点になることを確かめます。
    func testSwitchesAfterRequiredConsecutiveCountWithFirstMark() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertNil(confirmation.observe("B", at: mark(10), requiredCount: 3))
        XCTAssertNil(confirmation.observe("B", at: mark(11), requiredCount: 3))
        XCTAssertEqual(confirmation.current, "A")
        let change = confirmation.observe("B", at: mark(12), requiredCount: 3)
        XCTAssertEqual(change?.from, "A")
        XCTAssertEqual(change?.to, "B")
        XCTAssertEqual(change?.since, mark(10))
        XCTAssertEqual(confirmation.current, "B")
    }

    /// 責務: 2点だけ別の値が来て元に戻った時は切り替わらず、次の別の値で数え直すことを確かめます。
    func testInterruptedRunDoesNotSwitchAndRestartsCount() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertNil(confirmation.observe("B", at: mark(1), requiredCount: 3))
        XCTAssertNil(confirmation.observe("B", at: mark(2), requiredCount: 3))
        XCTAssertNil(confirmation.observe("A", at: mark(3), requiredCount: 3))
        XCTAssertNil(confirmation.observe("B", at: mark(4), requiredCount: 3))
        XCTAssertNil(confirmation.observe("B", at: mark(5), requiredCount: 3))
        let change = confirmation.observe("B", at: mark(6), requiredCount: 3)
        XCTAssertEqual(change?.since, mark(4))
        XCTAssertEqual(confirmation.current, "B")
    }

    /// 責務: 候補が別の値に変わったら、その値で数え直す(前の候補の回数を引き継がない)ことを確かめます。
    func testDifferentCandidateRestartsCount() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertNil(confirmation.observe("B", at: mark(1), requiredCount: 3))
        XCTAssertNil(confirmation.observe("B", at: mark(2), requiredCount: 3))
        XCTAssertNil(confirmation.observe("C", at: mark(3), requiredCount: 3))
        XCTAssertNil(confirmation.observe("C", at: mark(4), requiredCount: 3))
        XCTAssertEqual(confirmation.current, "A")
        let change = confirmation.observe("C", at: mark(5), requiredCount: 3)
        XCTAssertEqual(change?.to, "C")
        XCTAssertEqual(change?.since, mark(3))
    }

    /// 責務: 切り替わった後に元の値へ戻る時も、同じ回数が要ることを確かめます。
    func testSwitchingBackNeedsFullCountAgain() {
        var confirmation = Confirmation(initial: "A")
        for sequence in 1...2 { _ = confirmation.observe("B", at: mark(Int64(sequence)), requiredCount: 2) }
        XCTAssertEqual(confirmation.current, "B")
        XCTAssertNil(confirmation.observe("A", at: mark(3), requiredCount: 2))
        XCTAssertEqual(confirmation.current, "B")
        let change = confirmation.observe("A", at: mark(4), requiredCount: 2)
        XCTAssertEqual(change?.from, "B")
        XCTAssertEqual(change?.since, mark(3))
    }

    /// 責務: 必要な回数が1・0・負の時に、最初の点ですぐ切り替わることを確かめます。
    func testRequiredCountOfOneOrLessSwitchesImmediately() {
        for required in [1, 0, -5] {
            var confirmation = Confirmation(initial: "A")
            let change = confirmation.observe("B", at: mark(7), requiredCount: required)
            XCTAssertEqual(change?.to, "B", "requiredCount \(required)")
            XCTAssertEqual(change?.since, mark(7), "requiredCount \(required)")
            XCTAssertEqual(confirmation.current, "B")
        }
    }

    /// 責務: 切り替え待ちの途中で現在と同じ値が来たら、待ちが数え直しになることを確かめます。
    func testCurrentValueClearsPendingCandidate() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertNil(confirmation.observe("B", at: mark(1), requiredCount: 2))
        XCTAssertNil(confirmation.observe("A", at: mark(2), requiredCount: 2))
        XCTAssertNil(confirmation.observe("B", at: mark(3), requiredCount: 2))
        XCTAssertEqual(confirmation.current, "A")
    }

    /// 責務: reset が状態を即座に置き換え、切り替え待ちも消すことを確かめます。
    func testResetReplacesCurrentAndClearsPending() {
        var confirmation = Confirmation(initial: "A")
        XCTAssertNil(confirmation.observe("B", at: mark(1), requiredCount: 2))
        confirmation.reset(to: "Z")
        XCTAssertEqual(confirmation.current, "Z")
        XCTAssertNil(confirmation.observe("B", at: mark(2), requiredCount: 2))
        XCTAssertEqual(confirmation.current, "Z")
        XCTAssertEqual(confirmation.observe("B", at: mark(3), requiredCount: 2)?.since, mark(2))
    }
}
