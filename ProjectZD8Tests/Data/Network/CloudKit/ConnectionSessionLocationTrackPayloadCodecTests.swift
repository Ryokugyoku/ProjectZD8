import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrackPayloadCodec` の往復と出力形式を検証します。
///
/// 仕様: `encode` は JSON(`.sortedKeys, .withoutEscapingSlashes`)を LZFSE で圧縮したバイト列を返す。
/// `decode` は圧縮後のバイト列から元の軌跡を完全に復元する。検証の失敗は `CodecValidationTests` が扱う。
final class ConnectionSessionLocationTrackPayloadCodecTests: XCTestCase {
    /// 検証対象の符号化器です。
    private let codec = ConnectionSessionLocationTrackPayloadCodec()
    /// テスト用のセッションです。
    private let sessionID = CloudKitLocationTrackTestValues.sessionID
    /// テスト用の fingerprint です。
    private let fingerprint = CloudKitLocationTrackTestValues.accountFingerprint

    /// 符号化した軌跡を復号すると、元と等しい軌跡になることを検証します。
    ///
    /// 責務: 位置と事象の両方を含む軌跡の往復を確認します。
    func testRoundTripPreservesSamplesAndEvents() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 5, eventCount: 3)
        XCTAssertEqual(try roundTrip(track), track)
    }

    /// 任意フィールドが `nil` の位置も往復で `nil` のままであることを検証します。
    ///
    /// 責務: 標高・垂直精度・速度・進行方向の欠落を確認します。
    func testRoundTripPreservesAbsentOptionalFields() throws {
        let track = try CloudKitLocationTrackTestValues.trackWithoutOptionalFields()
        let decoded = try roundTrip(track)
        XCTAssertEqual(decoded, track)
        let fix = try XCTUnwrap(decoded.samples.first?.fix)
        XCTAssertNil(fix.altitudeMeters)
        XCTAssertNil(fix.verticalAccuracyMeters)
        XCTAssertNil(fix.speedMetersPerSecond)
        XCTAssertNil(fix.courseDegrees)
    }

    /// 緯度経度の端の値が往復で変わらないことを検証します。
    ///
    /// 責務: 緯度 ±90、経度 ±180 の境界を確認します。
    func testRoundTripPreservesExtremeCoordinates() throws {
        let corners: [(Double, Double)] = [(90, 180), (-90, -180), (90, -180), (-90, 180), (0, 0)]
        let samples = try corners.enumerated().map { index, corner in
            ConnectionSessionLocationSample(
                sequence: Int64(index),
                fix: try ConnectionSessionLocationTestValues.fix(
                    latitude: corner.0, longitude: corner.1, secondsAfterReference: Double(index)
                )
            )
        }
        let track = ConnectionSessionLocationTrack(sessionID: sessionID, samples: samples, events: [])
        XCTAssertEqual(try roundTrip(track), track)
    }

    /// `UInt64` の大きな単調時計の値が丸められずに往復することを検証します。
    ///
    /// 責務: 倍精度で表せない値(`UInt64.max`)を確認します。
    func testRoundTripPreservesLargeMonotonicNanoseconds() throws {
        let values: [UInt64] = [0, UInt64(Int64.max) + 1, UInt64.max]
        let samples = try values.enumerated().map { index, value in
            ConnectionSessionLocationSample(
                sequence: Int64(index),
                fix: try ConnectionSessionLocationTestValues.fix(
                    secondsAfterReference: Double(index), monotonicNanoseconds: value
                )
            )
        }
        let track = ConnectionSessionLocationTrack(sessionID: sessionID, samples: samples, events: [])
        XCTAssertEqual(try roundTrip(track).samples.map(\.fix.monotonicNanoseconds), values)
    }

    /// マイクロ秒の時刻が往復で変わらず、ペイロードにマイクロ秒の整数で入ることを検証します。
    ///
    /// 責務: 位置の観測時刻と事象の発生時刻のマイクロ秒精度を確認します。
    func testRoundTripPreservesMicrosecondTimestamps() throws {
        let observed = Date(timeIntervalSince1970: 1_800_000_000.125)
        let occurred = Date(timeIntervalSince1970: 1_800_000_001.015625)
        let fix = try XCTUnwrap(LocationFix(
            latitude: 35, longitude: 139, altitudeMeters: nil, horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: nil, speedMetersPerSecond: nil, courseDegrees: nil,
            observedAt: observed, monotonicNanoseconds: 1
        ))
        let track = ConnectionSessionLocationTrack(
            sessionID: sessionID,
            samples: [ConnectionSessionLocationSample(sequence: 0, fix: fix)],
            events: [ConnectionSessionLocationEvent(ordinal: 0, occurredAt: occurred, kind: .recording)]
        )
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        let json = try CloudKitLocationTrackTestValues.json(fromCompressed: encoded)
        let sample = try XCTUnwrap((json["samples"] as? [[String: Any]])?.first)
        let event = try XCTUnwrap((json["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(sample["observedAtMicroseconds"] as? Int64, 1_800_000_000_125_000)
        XCTAssertEqual(event["occurredAtMicroseconds"] as? Int64, 1_800_000_001_015_625)
        XCTAssertEqual(try codec.decode(encoded, expectedSessionID: sessionID, expectedAccountFingerprint: fingerprint), track)
    }

    /// 事象だけの軌跡も往復できることを検証します。
    ///
    /// 責務: サンプルが0件で事象だけのケースを確認します。
    func testRoundTripWithEventsOnly() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 0, eventCount: 4)
        XCTAssertEqual(try roundTrip(track), track)
    }

    /// サンプルだけの軌跡も往復できることを検証します。
    ///
    /// 責務: 事象が0件でサンプルだけのケースを確認します。
    func testRoundTripWithSamplesOnly() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 4, eventCount: 0)
        XCTAssertEqual(try roundTrip(track), track)
    }

    /// すべての事象の種類が往復で保たれることを検証します。
    ///
    /// 責務: 既知の kind 全種が復号で受け入れられることを確認します。
    func testRoundTripPreservesEveryEventKind() throws {
        let count = ConnectionSessionLocationEventKind.allCases.count
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 0, eventCount: count)
        XCTAssertEqual(try roundTrip(track).events.map(\.kind), ConnectionSessionLocationEventKind.allCases)
    }

    /// 出力が LZFSE で伸長でき、仕様のキーと値を持つ JSON であることを検証します。
    ///
    /// 責務: 版 1、小文字のセッション ID、fingerprint、サンプルと事象のキー名を確認します。
    func testEncodedBytesAreLZFSECompressedJSONWithSpecifiedKeys() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 1)
        let json = try CloudKitLocationTrackTestValues.json(fromCompressed: try codec.encode(track, accountFingerprint: fingerprint))
        XCTAssertEqual(json["formatVersion"] as? Int, 1)
        XCTAssertEqual(json["sessionID"] as? String, sessionID.rawValue.uuidString.lowercased())
        XCTAssertEqual(json["accountFingerprint"] as? String, fingerprint)
        let sample = try XCTUnwrap((json["samples"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(sample.keys), [
            "sequence", "observedAtMicroseconds", "monotonicNanoseconds", "latitude", "longitude",
            "altitudeMeters", "horizontalAccuracyMeters", "verticalAccuracyMeters",
            "speedMetersPerSecond", "courseDegrees"
        ])
        let event = try XCTUnwrap((json["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(event.keys), ["ordinal", "occurredAtMicroseconds", "kind"])
        XCTAssertEqual(event["kind"] as? String, ConnectionSessionLocationEventKind.allCases[0].rawValue)
    }

    /// 同じ入力からは同じバイト列が出ること(キー順が固定)を検証します。
    ///
    /// 責務: `.sortedKeys` による決定性を確認します。
    func testEncodeIsDeterministic() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 20, eventCount: 5)
        XCTAssertEqual(
            try codec.encode(track, accountFingerprint: fingerprint),
            try codec.encode(track, accountFingerprint: fingerprint)
        )
    }

    /// 圧縮により、同じ内容の素の JSON より小さくなることを検証します。
    ///
    /// 責務: 出力が圧縮されている(素の JSON ではない)ことを確認します。
    func testEncodedBytesAreSmallerThanPlainJSON() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 1_000, eventCount: 0)
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        let json = try CloudKitLocationTrackTestValues.json(fromCompressed: encoded)
        let plain = try JSONSerialization.data(withJSONObject: json)
        XCTAssertLessThan(encoded.count, plain.count)
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: encoded), "出力は素の JSON ではなく圧縮後のバイト列のはず")
    }

    /// 4時間分(14,400点)の符号化結果が 8 MB 未満であることを検証します。
    ///
    /// 責務: CloudKit に送るサイズが上限を超えないことを確認します。
    func testFourHoursOfSamplesEncodeBelowEightMegabytes() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 14_400, eventCount: 0)
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        XCTAssertLessThan(encoded.count, 8 * 1_024 * 1_024)
        XCTAssertEqual(try codec.decode(encoded, expectedSessionID: sessionID, expectedAccountFingerprint: fingerprint), track)
    }

    /// 符号化して復号します。
    ///
    /// 責務: テストが期待するセッションと fingerprint で往復します。
    private func roundTrip(_ track: ConnectionSessionLocationTrack) throws -> ConnectionSessionLocationTrack {
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        return try codec.decode(encoded, expectedSessionID: sessionID, expectedAccountFingerprint: fingerprint)
    }
}
