import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrackPayloadCodec` の符号化・復号時の検証を確認します。
///
/// 仕様: 空の軌跡の符号化は `.invalidState`。復号は版・セッション ID・fingerprint・番号の順序と重複・位置の範囲・
/// 事象の種類・バイト列の健全性を検証し、失敗は `.integrityConflict`。版が新しい時は `.unsupportedPayloadFormat`。
final class ConnectionSessionLocationTrackPayloadCodecValidationTests: XCTestCase {
    /// 検証対象の符号化器です。
    private let codec = ConnectionSessionLocationTrackPayloadCodec()
    /// テスト用のセッションです。
    private let sessionID = CloudKitLocationTrackTestValues.sessionID
    /// テスト用の fingerprint です。
    private let fingerprint = CloudKitLocationTrackTestValues.accountFingerprint

    /// 空の軌跡の符号化が `.invalidState` で失敗することを検証します。
    ///
    /// 責務: 点も事象も無い軌跡を送らないことを確認します。
    func testEncodeEmptyTrackThrowsInvalidState() {
        let empty = ConnectionSessionLocationTrack(sessionID: sessionID, samples: [], events: [])
        XCTAssertThrowsError(try codec.encode(empty, accountFingerprint: fingerprint)) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        }
    }

    /// 版 2 のペイロードが `.unsupportedPayloadFormat(version: 2)` になることを検証します。
    ///
    /// 責務: 新しい版のアプリが作ったデータを、壊れたデータと区別することを確認します。
    func testDecodeFormatVersionTwoThrowsUnsupportedPayloadFormat() throws {
        let data = try CloudKitLocationTrackTestValues.compress(CloudKitLocationTrackTestValues.payloadJSON(formatVersion: 2))
        XCTAssertThrowsError(try decode(data)) { error in
            XCTAssertEqual(error as? ConnectionSessionLocationTrackCloudError, .unsupportedPayloadFormat(version: 2))
        }
    }

    /// 期待するセッションと異なるセッションで復号すると `.integrityConflict` になることを検証します。
    ///
    /// 責務: 呼び出し側の期待するセッション ID の不一致を確認します。
    func testDecodeWithDifferentExpectedSessionThrowsIntegrityConflict() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0)
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        assertIntegrityConflict(
            try codec.decode(encoded, expectedSessionID: ConnectionSessionID(), expectedAccountFingerprint: fingerprint)
        )
    }

    /// ペイロード内のセッション ID が期待と異なる場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: ペイロードが別セッションのものである場合を確認します。
    func testDecodePayloadWithOtherSessionIDThrowsIntegrityConflict() throws {
        let json = CloudKitLocationTrackTestValues.payloadJSON(sessionID: UUID().uuidString.lowercased())
        assertIntegrityConflict(try decode(try CloudKitLocationTrackTestValues.compress(json)))
    }

    /// 期待する fingerprint と異なる場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 別のアカウントのペイロードを受け付けないことを確認します。
    func testDecodeWithDifferentExpectedFingerprintThrowsIntegrityConflict() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0)
        let encoded = try codec.encode(track, accountFingerprint: fingerprint)
        assertIntegrityConflict(
            try codec.decode(encoded, expectedSessionID: sessionID, expectedAccountFingerprint: CloudKitRecordDigest.accountFingerprint(for: "other"))
        )
    }

    /// ペイロード内の fingerprint が異なる場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: ペイロードが別アカウントのものである場合を確認します。
    func testDecodePayloadWithOtherFingerprintThrowsIntegrityConflict() throws {
        let json = CloudKitLocationTrackTestValues.payloadJSON(accountFingerprint: CloudKitRecordDigest.accountFingerprint(for: "other"))
        assertIntegrityConflict(try decode(try CloudKitLocationTrackTestValues.compress(json)))
    }

    /// サンプルの sequence が重複する場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 同じ番号が2回現れる場合を確認します。
    func testDecodeDuplicateSampleSequenceThrowsIntegrityConflict() throws {
        let samples = [1, 1].map { CloudKitLocationTrackTestValues.sampleJSON(sequence: Int64($0)) }
        assertIntegrityConflict(try decode(samples: samples))
    }

    /// サンプルの sequence が逆順の場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 昇順でない並びを確認します。
    func testDecodeDescendingSampleSequenceThrowsIntegrityConflict() throws {
        let samples = [2, 1].map { CloudKitLocationTrackTestValues.sampleJSON(sequence: Int64($0)) }
        assertIntegrityConflict(try decode(samples: samples))
    }

    /// サンプルの sequence が負の場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 0 未満の番号を確認します。
    func testDecodeNegativeSampleSequenceThrowsIntegrityConflict() throws {
        assertIntegrityConflict(try decode(samples: [CloudKitLocationTrackTestValues.sampleJSON(sequence: -1)]))
    }

    /// 事象の ordinal が重複・逆順・負の場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 事象の番号の3種類の不正を確認します。
    func testDecodeInvalidEventOrdinalsThrowIntegrityConflict() throws {
        for ordinals in [[1, 1], [2, 1], [-1]] {
            let events = ordinals.map { CloudKitLocationTrackTestValues.eventJSON(ordinal: $0) }
            assertIntegrityConflict(try decode(events: events), "ordinals=\(ordinals)")
        }
    }

    /// 緯度・経度が範囲外の場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: 緯度 91、緯度 -91、経度 181 の位置を確認します。
    func testDecodeOutOfRangeCoordinateThrowsIntegrityConflict() throws {
        var longitudeOut = CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)
        longitudeOut["longitude"] = 181.0
        let samples = [
            CloudKitLocationTrackTestValues.sampleJSON(sequence: 0, latitude: 91),
            CloudKitLocationTrackTestValues.sampleJSON(sequence: 0, latitude: -91),
            longitudeOut
        ]
        for sample in samples {
            assertIntegrityConflict(try decode(samples: [sample]))
        }
    }

    /// 位置の不変条件に反する値(負の精度、標高だけの組)で `.integrityConflict` になることを検証します。
    ///
    /// 責務: `LocationFix` が作れない値を復号が受け入れないことを確認します。
    func testDecodeValuesViolatingFixInvariantsThrowIntegrityConflict() throws {
        var negativeAccuracy = CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)
        negativeAccuracy["horizontalAccuracyMeters"] = -1.0
        var altitudeOnly = CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)
        altitudeOnly["altitudeMeters"] = 10.0
        var courseOut = CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)
        courseOut["courseDegrees"] = 360.0
        for sample in [negativeAccuracy, altitudeOnly, courseOut] {
            assertIntegrityConflict(try decode(samples: [sample]))
        }
    }

    /// 未知の事象の種類で `.integrityConflict` になることを検証します。
    ///
    /// 責務: kind が既知の rawValue でない場合を確認します。
    func testDecodeUnknownEventKindThrowsIntegrityConflict() throws {
        assertIntegrityConflict(try decode(events: [CloudKitLocationTrackTestValues.eventJSON(ordinal: 0, kind: "teleporting")]))
    }

    /// 必須キーの欠落で `.integrityConflict` になることを検証します。
    ///
    /// 責務: `samples` が無い JSON と、`latitude` が無い位置を確認します。
    func testDecodeMissingRequiredKeysThrowsIntegrityConflict() throws {
        var withoutSamples = CloudKitLocationTrackTestValues.payloadJSON()
        withoutSamples.removeValue(forKey: "samples")
        assertIntegrityConflict(try decode(try CloudKitLocationTrackTestValues.compress(withoutSamples)))
        var withoutLatitude = CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)
        withoutLatitude.removeValue(forKey: "latitude")
        assertIntegrityConflict(try decode(samples: [withoutLatitude]))
    }

    /// 壊れたバイト列で `.integrityConflict` になることを検証します。
    ///
    /// 責務: 空、圧縮でないバイト列、途中で切れた圧縮列、伸長できても JSON でない列を確認します。
    func testDecodeCorruptedBytesThrowIntegrityConflict() throws {
        let valid = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 50, eventCount: 2), accountFingerprint: fingerprint)
        let notJSON = try CloudKitLocationTrackTestValues.compress(rawBytes: Data("not json".utf8))
        let candidates: [(String, Data)] = [
            ("empty", Data()),
            ("garbage", Data(repeating: 0xFF, count: 64)),
            ("truncated", valid.prefix(valid.count / 2)),
            ("notJSON", notJSON)
        ]
        for (label, data) in candidates {
            assertIntegrityConflict(try decode(data), label)
        }
    }

    /// 正しい出力の末尾(終端マーカー)を書き換えると `.integrityConflict` になることを検証します。
    ///
    /// 責務: 正しい出力のバイトを書き換えて伸長を失敗させるケースを確認します。
    func testDecodeOfOverwrittenTailThrowsIntegrityConflict() throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 50, eventCount: 2)
        var data = try codec.encode(track, accountFingerprint: fingerprint)
        for index in (data.count - 8)..<data.count { data[index] = 0xFF }
        assertIntegrityConflict(try decode(data))
    }

    /// 復号を実行します。
    ///
    /// 責務: 固定のセッションと fingerprint を期待値にして復号します。
    private func decode(_ data: Data) throws -> ConnectionSessionLocationTrack {
        try codec.decode(data, expectedSessionID: sessionID, expectedAccountFingerprint: fingerprint)
    }

    /// 指定のサンプルと事象を持つペイロードを復号します。
    ///
    /// 責務: 既定が有効なペイロードの一部だけを差し替えて復号します。
    private func decode(
        samples: [[String: Any]] = [CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)],
        events: [[String: Any]] = []
    ) throws -> ConnectionSessionLocationTrack {
        let json = CloudKitLocationTrackTestValues.payloadJSON(samples: samples, events: events)
        return try decode(try CloudKitLocationTrackTestValues.compress(json))
    }

    /// 式が `.integrityConflict` で失敗することを確認します。
    ///
    /// 責務: 失敗の型と case を検証します。
    private func assertIntegrityConflict(
        _ expression: @autoclosure () throws -> ConnectionSessionLocationTrack,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .integrityConflict, message, file: file, line: line)
        }
    }
}
