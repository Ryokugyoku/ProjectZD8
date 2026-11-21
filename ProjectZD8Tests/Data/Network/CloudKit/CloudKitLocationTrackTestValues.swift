import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの CloudKit 符号化・レコード変換のテストが共有する値と、ペイロードを組み立てる補助です。
enum CloudKitLocationTrackTestValues {
    /// テストで使う固定のセッション識別値です。
    static let sessionID = ConnectionSessionID(rawValue: UUID(uuidString: "1B2C3D4E-0000-4000-8000-0000000000AB")!)
    /// テストで使う固定のアカウント識別子です。
    static let accountIdentifier = "account-A"
    /// 固定のアカウント識別子から仕様どおりに決まる fingerprint です(SHA-256 の16進)。
    static let accountFingerprint = CloudKitRecordDigest.accountFingerprint(for: accountIdentifier)

    /// 番号付きの位置と事象から成る軌跡を作ります。
    ///
    /// 責務: 互いに異なる有効な位置を `sampleCount` 点、事象を `eventCount` 件並べた軌跡を返します。
    /// - Parameters:
    ///   - sessionID: 軌跡のセッション。
    ///   - sampleCount: 位置の数。
    ///   - eventCount: 事象の数。
    /// - Returns: sequence と ordinal が 0 からの昇順の軌跡。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func track(
        sessionID: ConnectionSessionID = CloudKitLocationTrackTestValues.sessionID,
        sampleCount: Int,
        eventCount: Int
    ) throws -> ConnectionSessionLocationTrack {
        let samples = try (0..<sampleCount).map { index in
            ConnectionSessionLocationSample(
                sequence: Int64(index),
                fix: try ConnectionSessionLocationTestValues.fix(index: index)
            )
        }
        let kinds = ConnectionSessionLocationEventKind.allCases
        let events = (0..<eventCount).map { index in
            ConnectionSessionLocationEvent(
                ordinal: index,
                occurredAt: Date(timeIntervalSince1970: ConnectionSessionLocationTestValues.referenceSeconds + Double(index)),
                kind: kinds[index % kinds.count]
            )
        }
        return ConnectionSessionLocationTrack(sessionID: sessionID, samples: samples, events: events)
    }

    /// 任意値をすべて欠いた位置を1点だけ持つ軌跡を作ります。
    ///
    /// 責務: 標高・垂直精度・速度・進行方向が `nil` の位置の往復検証に使う軌跡を返します。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func trackWithoutOptionalFields() throws -> ConnectionSessionLocationTrack {
        let fix = try XCTUnwrap(LocationFix(
            latitude: 0, longitude: 0, altitudeMeters: nil, horizontalAccuracyMeters: 0,
            verticalAccuracyMeters: nil, speedMetersPerSecond: nil, courseDegrees: nil,
            observedAt: Date(timeIntervalSince1970: 0), monotonicNanoseconds: 0
        ))
        return ConnectionSessionLocationTrack(
            sessionID: sessionID,
            samples: [ConnectionSessionLocationSample(sequence: 0, fix: fix)],
            events: []
        )
    }

    /// 指定した JSON の辞書を、仕様どおり LZFSE で圧縮したバイト列にします。
    ///
    /// 責務: 改ざんしたペイロードを意味の検証の入力として作ります。
    /// - Throws: 符号化または圧縮に失敗した場合。
    static func compress(_ json: [String: Any]) throws -> Data {
        let raw = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return try compress(rawBytes: raw)
    }

    /// 任意のバイト列を LZFSE で圧縮します。
    ///
    /// 責務: JSON として壊れたバイト列を、伸長は成功する形で作ります。
    /// - Throws: 圧縮に失敗した場合。
    static func compress(rawBytes: Data) throws -> Data {
        try (rawBytes as NSData).compressed(using: .lzfse) as Data
    }

    /// 圧縮されたペイロードを伸長して JSON の辞書にします。
    ///
    /// 責務: 正しい出力の中身を取り出し、改ざんの土台にします。
    /// - Throws: 伸長または JSON の読み取りに失敗した場合。
    static func json(fromCompressed data: Data) throws -> [String: Any] {
        let raw = try (data as NSData).decompressed(using: .lzfse) as Data
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
    }

    /// 位置1点分の JSON の辞書を作ります。
    ///
    /// 責務: 必須フィールドだけを持つ有効な位置の辞書を返します。
    static func sampleJSON(sequence: Int64, latitude: Double = 35.0) -> [String: Any] {
        [
            "sequence": sequence,
            "observedAtMicroseconds": 1_800_000_000_000_000 + sequence,
            "monotonicNanoseconds": 1_000 + sequence,
            "latitude": latitude,
            "longitude": 139.0,
            "horizontalAccuracyMeters": 5.0
        ]
    }

    /// 事象1件分の JSON の辞書を作ります。
    ///
    /// 責務: 指定の番号と種類の事象の辞書を返します。
    static func eventJSON(ordinal: Int, kind: String = "recording") -> [String: Any] {
        ["ordinal": ordinal, "occurredAtMicroseconds": 1_800_000_000_000_000 + Int64(ordinal), "kind": kind]
    }

    /// ペイロード全体の JSON の辞書を作ります。
    ///
    /// 責務: 既定は固定のセッションと fingerprint で一致する有効な内容を返します。
    static func payloadJSON(
        formatVersion: Int64 = 1,
        sessionID: String = CloudKitLocationTrackTestValues.sessionID.rawValue.uuidString.lowercased(),
        accountFingerprint: String = CloudKitLocationTrackTestValues.accountFingerprint,
        samples: [[String: Any]] = [CloudKitLocationTrackTestValues.sampleJSON(sequence: 0)],
        events: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "formatVersion": formatVersion,
            "sessionID": sessionID,
            "accountFingerprint": accountFingerprint,
            "samples": samples,
            "events": events
        ]
    }

    /// 一意な一時ディレクトリを作ります。
    ///
    /// 責務: テストが作る一時ファイルの置き場を用意します。呼び出し側が tearDown で消します。
    /// - Throws: ディレクトリを作れない場合。
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocationTrackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
