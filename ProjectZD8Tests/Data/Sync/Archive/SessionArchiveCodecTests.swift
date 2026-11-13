import Foundation
import XCTest
@testable import ProjectZD8

/// セッションアーカイブの符号化・検証を確認します。
final class SessionArchiveCodecTests: XCTestCase {
    private let codec = SessionArchiveCodec()

    /// 責務: 検証用のアーカイブを作ります。
    private func makeArchive(formatVersion: Int = SessionArchive.currentFormatVersion) -> SessionArchive {
        let session = DriveSession(
            vehicleID: VehicleID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            endReason: .userStopped,
            isDemo: false,
            adapterName: "vLinker",
            adapterTransport: .bluetoothLowEnergy,
            platform: .mac,
            deviceID: "d",
            deviceName: "Mac",
            appVersion: "1.0",
            appBuild: "1",
            pollingPolicyVersion: 1,
            sampleCount: 2,
            respondedCount: 1,
            payloadByteCount: 2,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
        let request = OBDPIDRequest(service: 1, pid: 0x0C)
        return SessionArchive(
            formatVersion: formatVersion,
            session: session,
            pids: [SessionPID(ordinal: 0, request: request, header: 0x7E0, support: .supported, isCollectionEnabled: true, isFastGroup: true, definitionRevision: 1, requiredByteCount: 2, formula: "(A*256+B)/4", unit: "rpm", minimumValue: 0, maximumValue: 16_383)],
            samples: [
                SessionSample(sequence: 0, tick: 0, elapsedMicroseconds: 0, request: request, outcome: .responded, payload: Data([0x0B, 0xB8])),
                SessionSample(sequence: 1, tick: 1, elapsedMicroseconds: 100_000, request: request, outcome: .timedOut),
            ]
        )
    }

    /// 責務: 符号化して復号すると同じアーカイブに戻り、検証値が圧縮バイト列のSHA-256であることを確認します。
    func testRoundTripPreservesArchiveAndDigestCoversCompressedBytes() throws {
        let archive = makeArchive()
        let encoded = try codec.encode(archive)
        XCTAssertEqual(encoded.digest, SessionArchiveCodec.digest(of: encoded.data))
        XCTAssertEqual(encoded.digest.count, 64)
        XCTAssertEqual(try codec.decode(encoded.data, expectedDigest: encoded.digest), archive)
    }

    /// 責務: 同じ内容は同じバイト列になる(キー整列)ことを確認します。
    func testEncodingIsDeterministic() throws {
        let archive = makeArchive()
        XCTAssertEqual(try codec.encode(archive), try codec.encode(archive))
    }

    /// 責務: 検証値が合わない場合に型付きの失敗になることを確認します。
    func testDecodeRejectsDigestMismatch() throws {
        var data = try codec.encode(makeArchive()).data
        let expected = SessionArchiveCodec.digest(of: data)
        data[data.startIndex] ^= 0xFF
        XCTAssertThrowsError(try codec.decode(data, expectedDigest: expected)) { error in
            XCTAssertEqual(error as? SessionArchiveCodecError, .digestMismatch)
        }
    }

    /// 責務: 未対応の形式版を拒否することを確認します。
    func testDecodeRejectsUnsupportedFormatVersion() throws {
        let encoded = try codec.encode(makeArchive(formatVersion: 99))
        XCTAssertThrowsError(try codec.decode(encoded.data, expectedDigest: encoded.digest)) { error in
            XCTAssertEqual(error as? SessionArchiveCodecError, .unsupportedFormatVersion(99))
        }
    }

    /// 責務: 検証値は合うが展開できないデータを不正として拒否することを確認します。
    func testDecodeRejectsMalformedData() {
        let garbage = Data("not compressed".utf8)
        XCTAssertThrowsError(try codec.decode(garbage, expectedDigest: SessionArchiveCodec.digest(of: garbage))) { error in
            XCTAssertEqual(error as? SessionArchiveCodecError, .malformed)
        }
    }
}
