import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEWriteChunker.chunks(of:maximumLength:)` の分割と境界値を検証します。
final class BLEWriteChunkerTests: XCTestCase {
    private let chunker = BLEWriteChunker()

    /// 最大長が0以下なら明示的に失敗します。
    ///
    /// 責務: 0と負の最大長がそれぞれ値付きの `invalidMaximumLength` になることを確認します。
    func testNonPositiveMaximumLengthThrows() {
        for maximumLength in [0, -1, Int.min] {
            XCTAssertThrowsError(try chunker.chunks(of: Data([1, 2, 3]), maximumLength: maximumLength)) { error in
                XCTAssertEqual(error as? BLEWriteChunker.Failure, .invalidMaximumLength(maximumLength))
            }
        }
    }

    /// 空データでも最大長が不正なら失敗します。
    ///
    /// 責務: 最大長の検証が空データの判定より先に行われることを確認します。
    func testEmptyDataWithInvalidMaximumLengthThrows() {
        XCTAssertThrowsError(try chunker.chunks(of: Data(), maximumLength: 0)) { error in
            XCTAssertEqual(error as? BLEWriteChunker.Failure, .invalidMaximumLength(0))
        }
    }

    /// 空データは空のチャンク列になります。
    ///
    /// 責務: 空データから空チャンクを作らないことを確認します。
    func testEmptyDataProducesNoChunks() throws {
        XCTAssertEqual(try chunker.chunks(of: Data(), maximumLength: 4), [])
    }

    /// 1バイトは1チャンクになります。
    ///
    /// 責務: 最小データがそのまま1チャンクになることを確認します。
    func testSingleByteProducesSingleChunk() throws {
        XCTAssertEqual(try chunker.chunks(of: Data([0xAB]), maximumLength: 4), [Data([0xAB])])
    }

    /// ちょうど最大長のデータは分割されません。
    ///
    /// 責務: 境界ちょうどで1チャンクのままであることを確認します。
    func testDataOfExactlyMaximumLengthIsNotSplit() throws {
        let data = Data([1, 2, 3, 4])
        XCTAssertEqual(try chunker.chunks(of: data, maximumLength: 4), [data])
    }

    /// 最大長+1のデータは最大長と1バイトに分割されます。
    ///
    /// 責務: 境界を1超えた時の分割位置を確認します。
    func testDataOfMaximumLengthPlusOneSplitsIntoTwo() throws {
        XCTAssertEqual(try chunker.chunks(of: Data([1, 2, 3, 4, 5]), maximumLength: 4), [Data([1, 2, 3, 4]), Data([5])])
    }

    /// 最大長の整数倍のデータは最大長ちょうどのチャンクだけになります。
    ///
    /// 責務: 端数チャンクや空チャンクができないことを確認します。
    func testMultipleOfMaximumLengthProducesOnlyFullChunks() throws {
        let data = Data(0..<12)
        let chunks = try chunker.chunks(of: data, maximumLength: 4)
        XCTAssertEqual(chunks, [Data(0..<4), Data(4..<8), Data(8..<12)])
    }

    /// 最大長1では1バイトずつ順に分割されます。
    ///
    /// 責務: 最小の最大長で順序と内容が保たれることを確認します。
    func testMaximumLengthOneSplitsEveryByteInOrder() throws {
        let data = Data([9, 8, 7])
        XCTAssertEqual(try chunker.chunks(of: data, maximumLength: 1), [Data([9]), Data([8]), Data([7])])
    }

    /// 最大長がデータより大きくても1チャンクです。
    ///
    /// 責務: 大きな最大長で分割されないことを確認します。
    func testMaximumLengthLargerThanDataProducesSingleChunk() throws {
        let data = Data(0..<10)
        XCTAssertEqual(try chunker.chunks(of: data, maximumLength: Int.max), [data])
    }

    /// 開始位置が0でないスライスも元の順序で正しく分割されます。
    ///
    /// 責務: `startIndex` が0でないDataで連結結果が元のバイト列と一致し、各チャンクが最大長以下であることを確認します。
    func testSliceWithNonZeroStartIndexIsSplitCorrectly() throws {
        let slice = Data(0..<20)[5..<15]
        let chunks = try chunker.chunks(of: slice, maximumLength: 3)
        XCTAssertEqual(chunks.map { Array($0) }, [[5, 6, 7], [8, 9, 10], [11, 12, 13], [14]])
        XCTAssertEqual(chunks.reduce(Data(), +), Data(slice))
    }
}
