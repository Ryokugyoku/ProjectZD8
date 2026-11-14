import Foundation
import XCTest
@testable import ProjectZD8

/// `BLEAdapterLink.write(_:)` の分割・書き込み種別・送信制御・順序・未接続時の失敗を検証します(受け入れ条件9)。
@MainActor
final class BLEAdapterLinkWriteTests: XCTestCase {
    private typealias Harness = BLEAdapterLinkTestHarness
    private typealias Fixtures = BLEUARTCapabilityFixtures

    /// 応答なし書き込みの最大書き込み長です。
    private let withoutResponseMTU = 8
    /// 応答あり書き込みの最大書き込み長です。
    private let withResponseMTU = 5

    /// 境界値の長さで、最大長以下のチャンクへ分割され連結すると元データに一致します(応答なし)。
    ///
    /// 責務: 空・1バイト・ちょうどMTU・MTU+1・MTUの整数倍の各長さで分割と連結を確認します。
    func testWriteSplitsIntoChunksWithinMaximumLengthAndPreservesBytes() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithoutResponseFFF2)
        defer { harness.tearDown() }
        let mtu = withoutResponseMTU

        for length in [0, 1, mtu, mtu + 1, mtu * 3] {
            let before = harness.peripheral.writtenChunks.count
            let data = Self.bytes(count: length, seed: UInt8(length % 251))
            let attempt = harness.beginWrite(data)
            try await BLEBoundedWaiter.waitUntil("write length=\(length)") { attempt.isFinished }

            XCTAssertEqual(attempt.outcome, .succeeded, "length=\(length)")
            let chunks = Array(harness.peripheral.writtenChunks.dropFirst(before))
            XCTAssertEqual(chunks.reduce(Data(), +), data, "length=\(length)")
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= mtu }, "length=\(length) chunks=\(chunks.map(\.count))")
            if length > 0, length <= mtu {
                XCTAssertEqual(chunks.count, 1, "最大長以下は分割しません length=\(length)")
            }
            if length > mtu {
                XCTAssertGreaterThan(chunks.count, 1, "最大長を超えたら分割します length=\(length)")
            }
        }
    }

    /// 応答なし書き込みが使える特性では応答なしで、解決されたwrite特性へ書き込みます。
    ///
    /// 責務: 両方の書き込みが使えるFFF2で、全チャンクが応答なし・FFF2/FFF0宛てであることを確認します。
    func testWriteUsesWithoutResponseOnResolvedWriteCharacteristicWhenAvailable() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeBothFFF2)
        defer { harness.tearDown() }
        let data = Self.bytes(count: withoutResponseMTU + 3, seed: 7)

        let attempt = harness.beginWrite(data)
        try await BLEBoundedWaiter.waitUntil("write without response") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(harness.peripheral.writeCalls, [
            .writeValue(data.prefix(withoutResponseMTU), characteristicUUID: Fixtures.fff2Write, serviceUUID: Fixtures.fff0Service, kind: .withoutResponse),
            .writeValue(data.dropFirst(withoutResponseMTU), characteristicUUID: Fixtures.fff2Write, serviceUUID: Fixtures.fff0Service, kind: .withoutResponse)
        ])
    }

    /// 応答なしが使えなければ応答ありで書き、完了通知が届くまで次のチャンクを出しません。
    ///
    /// 責務: 応答ありの各チャンクが完了通知ごとに1つずつ出て、最後の完了で書き込みが終わることを確認します。
    func testWriteWithResponseWaitsForCompletionBeforeNextChunk() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let data = Self.bytes(count: withResponseMTU * 2 + 2, seed: 30)

        let attempt = harness.beginWrite(data)
        try await BLEBoundedWaiter.waitUntil("first chunk") { harness.peripheral.writtenChunks.count >= 1 }

        XCTAssertEqual(harness.peripheral.writtenChunks.count, 1)
        for expectedCount in 2...3 {
            XCTAssertFalse(attempt.isFinished)
            emitWriteCompleted(harness)
            XCTAssertEqual(harness.peripheral.writtenChunks.count, expectedCount)
        }
        XCTAssertFalse(attempt.isFinished, "最後のチャンクの完了通知前に終わってはいけません")
        emitWriteCompleted(harness)
        try await BLEBoundedWaiter.waitUntil("write completion") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(harness.peripheral.writtenChunks.reduce(Data(), +), data)
        XCTAssertTrue(harness.peripheral.writeCalls.allSatisfy {
            $0 == .writeValue(Self.chunkData($0), characteristicUUID: Fixtures.fff2Write, serviceUUID: Fixtures.fff0Service, kind: .withResponse)
        })
    }

    /// 応答なしは送信不可の間は出さず、送信可能通知の後に続きを出します。
    ///
    /// 責務: 送信可能回数を1ずつ与え、通知ごとに1チャンクだけ進み、最後に成功することを確認します。
    func testWriteWithoutResponseResumesOnlyAfterReadyToSend() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithoutResponseFFF2)
        defer { harness.tearDown() }
        harness.peripheral.withoutResponseSendCredits = 1
        let data = Self.bytes(count: withoutResponseMTU * 3, seed: 90)

        let attempt = harness.beginWrite(data)
        try await BLEBoundedWaiter.waitUntil("first chunk") { harness.peripheral.writtenChunks.count >= 1 }

        XCTAssertEqual(harness.peripheral.writtenChunks.count, 1)
        XCTAssertFalse(attempt.isFinished)
        harness.peripheral.withoutResponseSendCredits = 1
        harness.peripheral.emit(.isReadyToSendWriteWithoutResponse)
        XCTAssertEqual(harness.peripheral.writtenChunks.count, 2)
        harness.peripheral.withoutResponseSendCredits = 5
        harness.peripheral.emit(.isReadyToSendWriteWithoutResponse)
        try await BLEBoundedWaiter.waitUntil("write completion") { attempt.isFinished }

        XCTAssertEqual(attempt.outcome, .succeeded)
        XCTAssertEqual(harness.peripheral.writtenChunks, [
            data.prefix(withoutResponseMTU),
            data.dropFirst(withoutResponseMTU).prefix(withoutResponseMTU),
            data.suffix(withoutResponseMTU)
        ].map { Data($0) })
    }

    /// 連続した2回の `write` のチャンクは呼び出し順に並び、混ざりません。
    ///
    /// 責務: 1回目が応答待ちの間に2回目を呼び、全チャンクが1回目→2回目の順で連結されることを確認します。
    func testConsecutiveWritesAreSentInCallOrderWithoutInterleaving() async throws {
        let harness = makeReadyHarness(write: Fixtures.writeWithResponseFFF2)
        defer { harness.tearDown() }
        let first = Self.bytes(count: withResponseMTU * 2 + 1, seed: 1)
        let second = Self.bytes(count: withResponseMTU + 2, seed: 101)
        let firstAttempt = harness.beginWrite(first)
        try await BLEBoundedWaiter.waitUntil("first write started") { harness.peripheral.writtenChunks.count >= 1 }
        let secondAttempt = harness.beginWrite(second)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.peripheral.writtenChunks.count, 1, "1回目の応答待ち中に2回目のチャンクを出してはいけません")

        for _ in 0..<5 where !secondAttempt.isFinished {
            emitWriteCompleted(harness)
            try await BLEBoundedWaiter.settle(polls: 2)
        }
        try await BLEBoundedWaiter.waitUntil("both writes") { firstAttempt.isFinished && secondAttempt.isFinished }

        XCTAssertEqual(firstAttempt.outcome, .succeeded)
        XCTAssertEqual(secondAttempt.outcome, .succeeded)
        XCTAssertEqual(harness.peripheral.writtenChunks.count, 5)
        XCTAssertEqual(harness.peripheral.writtenChunks.reduce(Data(), +), first + second)
    }

    /// `ready` でない時の `write` は `notReady` で失敗し、何も書き込みません。
    ///
    /// 責務: 未開始・接続中・探索中・切断後のそれぞれで明示的なエラーになることを確認します。
    func testWriteWhenNotReadyFailsWithNotReady() async throws {
        let harness = Harness()
        defer { harness.tearDown() }
        let steps: [(String, () -> Void)] = [
            ("idle", {}),
            ("connecting", { harness.startConnectingViaRetrieve() }),
            ("discovering", { harness.emitConnected() }),
            ("disconnected", { harness.central.setPowerState(.poweredOff) })
        ]

        for (label, step) in steps {
            step()
            let attempt = harness.beginWrite(Data([0x41, 0x54, 0x5A, 0x0D]))
            try await BLEBoundedWaiter.waitUntil("write in \(label)") { attempt.isFinished }
            XCTAssertEqual(attempt.outcome, .failed(.notReady), label)
        }
        XCTAssertEqual(harness.peripheral.writtenChunks, [])
    }

    /// 指定の書き込み能力で `ready` まで進めた準備を返します。
    ///
    /// 責務: 種別ごとに異なる最大書き込み長を設定し、FFF0構成で `ready` まで進めます。
    /// - Parameter write: FFF2の能力。
    /// - Returns: `ready` のリンクの準備。
    private func makeReadyHarness(write: AppleBluetoothCharacteristicCapability) -> Harness {
        let harness = Harness()
        harness.peripheral.maximumWriteLengths = [.withoutResponse: withoutResponseMTU, .withResponse: withResponseMTU]
        harness.driveToReady(write: write)
        XCTAssertEqual(harness.link.state, .ready)
        return harness
    }

    /// FFF2への応答あり書き込み完了通知を流します。
    ///
    /// 責務: 1チャンク分の書き込み完了を成功として通知します。
    /// - Parameter harness: 通知先の準備。
    private func emitWriteCompleted(_ harness: Harness) {
        harness.peripheral.emit(.didWriteValue(characteristicUUID: Fixtures.fff2Write, errorDescription: nil))
    }

    /// 書き込み呼び出しのバイト列を取り出します。
    ///
    /// 責務: 書き込み呼び出しからデータを返し、他の呼び出しは空にします。
    /// - Parameter call: ペリフェラル呼び出し。
    /// - Returns: 書き込まれたバイト列。
    private static func chunkData(_ call: BLEPeripheralRoleFake.Call) -> Data {
        if case .writeValue(let data, _, _, _) = call { data } else { Data() }
    }

    /// 位置ごとに異なる値を持つバイト列を生成します。
    ///
    /// 責務: 連結の取り違えを検出できるよう、開始値から1ずつ増えるバイト列を返します。
    /// - Parameters:
    ///   - count: バイト数。
    ///   - seed: 開始値。
    /// - Returns: バイト列。
    private static func bytes(count: Int, seed: UInt8) -> Data {
        Data((0..<count).map { seed &+ UInt8(truncatingIfNeeded: $0) })
    }
}
