import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBConnectionSessionCANFrameRepository` の保存・読込・一括保存の原子性を仕様から検証します。
final class GRDBConnectionSessionCANFrameRepositoryTests: XCTestCase {
    /// 一括保存を失敗させる欠陥の種類です。
    private enum Defect: CaseIterable {
        /// 既存行と記録順序が重複します。
        case duplicateSequence
        /// 存在しないセグメント番号を指します。
        case missingSegment
        /// 0x1FFFFFFFを超える識別子です。
        case identifierTooLarge
        /// 65バイトのpayloadです。
        case payloadTooLong
        /// `Int64` に収まらない単調時計値です。
        case monotonicBeyondInt64
    }

    /// 欠陥を持つ1件のフレームを生成します。
    ///
    /// 責務: 指定欠陥だけを持つ、指定記録順序のフレームを返します。
    /// - Parameters:
    ///   - defect: 持たせる欠陥。
    ///   - sequence: 欠陥なしの場合の記録順序(重複欠陥では既存の0を使用)。
    /// - Returns: 欠陥付きフレーム。
    private static func defective(_ defect: Defect, sequence: Int64) -> CANFrameObservation {
        switch defect {
        case .duplicateSequence: GRDBSegmentationRepositoryFixtures.frame(sequence: 0)
        case .missingSegment: GRDBSegmentationRepositoryFixtures.frame(sequence: sequence, segment: 9)
        case .identifierTooLarge: GRDBSegmentationRepositoryFixtures.frame(sequence: sequence, identifier: 0x2000_0000)
        case .payloadTooLong: GRDBSegmentationRepositoryFixtures.frame(sequence: sequence, payload: [UInt8](repeating: 0, count: 65))
        case .monotonicBeyondInt64: GRDBSegmentationRepositoryFixtures.frame(sequence: sequence, monotonic: UInt64(Int64.max) + 1)
        }
    }

    /// セグメント0・1を持つ検証用の組立てを返します。
    ///
    /// 責務: フレームの所属先となる2件の未終了セグメントを保存した組立てを用意します。
    private func makeFixtures() throws -> GRDBSegmentationRepositoryFixtures {
        let fixtures = try GRDBSegmentationRepositoryFixtures()
        for ordinal in 0...1 {
            try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: ordinal), for: fixtures.sessionID)
        }
        return fixtures
    }

    // MARK: - saveFrames / frames(for:)

    /// 保存した配列が等しく読めます。
    ///
    /// 責務: 複数セグメントにまたがるフレームの往復一致(時刻はマイクロ秒丸め)を確認します。
    func testSaveFramesRoundTrips() throws {
        let fixtures = try makeFixtures()
        let frames = [
            GRDBSegmentationRepositoryFixtures.frame(sequence: 0, segment: 0, identifier: 0x7E8, payload: [1, 2, 3]),
            GRDBSegmentationRepositoryFixtures.frame(sequence: 1, segment: 1, identifier: 0x18DA_F110, payload: [0xFF])
        ]

        try fixtures.frames.saveFrames(frames, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID), frames)
    }

    /// 受信時刻はマイクロ秒精度へ最近傍丸めで保存されます。
    ///
    /// 責務: 0.6マイクロ秒の端数が切り上げられることを確認します。
    func testReceivedAtIsRoundedToNearestMicrosecond() throws {
        let fixtures = try makeFixtures()
        let frame = CANFrameObservation(
            sequence: 0, segmentOrdinal: 0, receivedAt: Date(timeIntervalSince1970: 100.0000006),
            monotonicNanoseconds: 1, canIdentifier: 1, payload: []
        )

        try fixtures.frames.saveFrames([frame], for: fixtures.sessionID)

        XCTAssertEqual(
            try fixtures.frames.frames(for: fixtures.sessionID).first?.receivedAt, Date(timeIntervalSince1970: 100.000001)
        )
    }

    /// 保存順が逆でも `sequence` 昇順で返ります。
    ///
    /// 責務: 降順で渡した配列が昇順で読めることを確認します。
    func testFramesAreReturnedInAscendingSequenceOrder() throws {
        let fixtures = try makeFixtures()

        try fixtures.frames.saveFrames([4, 2, 3, 0, 1].map { GRDBSegmentationRepositoryFixtures.frame(sequence: $0) }, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID).map(\.sequence), [0, 1, 2, 3, 4])
    }

    /// 空配列の保存は成功し、何も増えません。
    ///
    /// 責務: 空配列が成功し行数が変わらないことを確認します。
    func testSavingEmptyArraySucceedsWithoutRows() throws {
        let fixtures = try makeFixtures()

        try fixtures.frames.saveFrames([], for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.rowCounts().frames, 0)
        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID), [])
    }

    /// 識別子とpayloadの境界値が往復します。
    ///
    /// 責務: 識別子0・0x1FFFFFFF、payload 0・64バイトの保存と読込を確認します。
    func testIdentifierAndPayloadBoundariesRoundTrip() throws {
        let fixtures = try makeFixtures()
        let frames = [
            GRDBSegmentationRepositoryFixtures.frame(sequence: 0, identifier: 0, payload: []),
            GRDBSegmentationRepositoryFixtures.frame(sequence: 1, identifier: 0x1FFF_FFFF, payload: [UInt8](repeating: 0xAB, count: 64)),
            GRDBSegmentationRepositoryFixtures.frame(sequence: 2, payload: [UInt8](repeating: 0, count: 64))
        ]

        try fixtures.frames.saveFrames(frames, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID), frames)
    }

    /// 他セッションのフレームは混ざりません。
    ///
    /// 責務: セッション単位の絞り込みと、行のないセッションで空配列になることを確認します。
    func testFramesAreScopedToSession() throws {
        let fixtures = try makeFixtures()
        let other = try fixtures.makeOtherSession()
        try fixtures.segments.beginSegment(GRDBSegmentationRepositoryFixtures.segment(ordinal: 0), for: other)
        try fixtures.frames.saveFrames([GRDBSegmentationRepositoryFixtures.frame(sequence: 0, identifier: 1)], for: fixtures.sessionID)
        try fixtures.frames.saveFrames([GRDBSegmentationRepositoryFixtures.frame(sequence: 0, identifier: 2)], for: other)

        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID).map(\.canIdentifier), [1])
        XCTAssertEqual(try fixtures.frames.frames(for: other).map(\.canIdentifier), [2])
        XCTAssertEqual(try fixtures.frames.frames(for: ConnectionSessionID()), [])
    }

    // MARK: - 一括保存の原子性

    /// 配列内の記録順序重複は `integrityConflict` で、そのチャンクは1行も残りません。
    ///
    /// 責務: 配列の途中の重複で、重複より前の要素も含めて全体がロールバックされることを確認します。
    func testDuplicateSequenceWithinChunkLeavesNoRows() throws {
        let fixtures = try makeFixtures()
        let chunk = [0, 1, 2, 2, 3].map { GRDBSegmentationRepositoryFixtures.frame(sequence: Int64($0)) }

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.frames.saveFrames(chunk, for: fixtures.sessionID)
        }

        XCTAssertEqual(try fixtures.rowCounts().frames, 0)
    }

    /// 欠陥が先頭・途中・末尾のどこにあっても、そのチャンクは残らず先行チャンクは残ります。
    ///
    /// 責務: 5種類の欠陥×3つの位置の全組み合わせで `integrityConflict` と、先行チャンクの保持を確認します。
    func testFailingChunkLeavesNoRowsAndKeepsEarlierChunks() throws {
        let fixtures = try makeFixtures()
        let committed = [0, 1, 2].map { GRDBSegmentationRepositoryFixtures.frame(sequence: Int64($0)) }
        try fixtures.frames.saveFrames(committed, for: fixtures.sessionID)

        for defect in Defect.allCases {
            for position in 0...2 {
                var chunk = [10, 11, 12].map { GRDBSegmentationRepositoryFixtures.frame(sequence: Int64($0)) }
                chunk[position] = Self.defective(defect, sequence: Int64(10 + position))

                assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
                    try fixtures.frames.saveFrames(chunk, for: fixtures.sessionID)
                }

                XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID), committed, "\(defect) @\(position)")
            }
        }
    }

    /// 失敗したチャンクの後でも、正しいチャンクは保存できます。
    ///
    /// 責務: 失敗が以降の保存を妨げず、重複していた記録順序も再利用できることを確認します。
    func testSavingSucceedsAfterFailedChunk() throws {
        let fixtures = try makeFixtures()
        let bad = [
            GRDBSegmentationRepositoryFixtures.frame(sequence: 0),
            GRDBSegmentationRepositoryFixtures.frame(sequence: 1, identifier: 0x2000_0000)
        ]
        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.frames.saveFrames(bad, for: fixtures.sessionID)
        }
        let good = [0, 1].map { GRDBSegmentationRepositoryFixtures.frame(sequence: Int64($0)) }

        try fixtures.frames.saveFrames(good, for: fixtures.sessionID)

        XCTAssertEqual(try fixtures.frames.frames(for: fixtures.sessionID), good)
    }

    /// 存在しないセッションへの保存は `integrityConflict` で、行は増えません。
    ///
    /// 責務: 親セッション不在(親セグメント不在)の拒否を確認します。
    func testSavingForMissingSessionIsIntegrityConflict() throws {
        let fixtures = try makeFixtures()

        assertThrowsError(ConnectionSessionRepositoryError.integrityConflict) {
            try fixtures.frames.saveFrames([GRDBSegmentationRepositoryFixtures.frame(sequence: 0)], for: ConnectionSessionID())
        }

        XCTAssertEqual(try fixtures.rowCounts().frames, 0)
    }
}
