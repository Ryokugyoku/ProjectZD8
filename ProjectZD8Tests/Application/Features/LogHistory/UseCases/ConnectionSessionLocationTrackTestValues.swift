import Foundation
@testable import ProjectZD8

/// 走行ルート同期のテストが共有する軌跡・同期記録・digest の値を生成します。
enum ConnectionSessionLocationTrackTestValues {
    /// 状態変化の時刻の基準(1970年起点の秒)です。
    static let eventReferenceSeconds: TimeInterval = 1_800_000_000

    /// N点のサンプルと M件の状態変化を持つ軌跡を作ります。
    ///
    /// 責務: 番号が 0 からの連番で、点ごとに区別できる位置と、種類が巡回する状態変化を持つ軌跡を返します。
    /// - Parameters:
    ///   - sessionID: 軌跡の接続セッション。
    ///   - sampleCount: サンプルの件数(0 以上)。
    ///   - eventCount: 状態変化の件数(0 以上)。
    ///   - sampleOffset: 位置の値をずらす量。同じ件数でも内容の違う軌跡を作る時に使います。
    /// - Returns: sequence・ordinal が昇順の軌跡。
    /// - Throws: 位置を作れない場合のテスト失敗。
    static func track(
        sessionID: ConnectionSessionID,
        sampleCount: Int,
        eventCount: Int = 0,
        sampleOffset: Int = 0
    ) throws -> ConnectionSessionLocationTrack {
        let samples = try (0..<sampleCount).map { index in
            ConnectionSessionLocationSample(
                sequence: Int64(index),
                fix: try ConnectionSessionLocationTestValues.fix(index: index + sampleOffset)
            )
        }
        return ConnectionSessionLocationTrack(
            sessionID: sessionID,
            samples: samples,
            events: events(count: eventCount)
        )
    }

    /// 点も状態変化も無い軌跡を作ります。
    ///
    /// 責務: 行が無いセッションの読み取り結果に当たる空の軌跡を返します。
    /// - Parameter sessionID: 軌跡の接続セッション。
    /// - Returns: 空の軌跡。
    static func emptyTrack(sessionID: ConnectionSessionID) -> ConnectionSessionLocationTrack {
        ConnectionSessionLocationTrack(sessionID: sessionID, samples: [], events: [])
    }

    /// 同期記録を作ります。
    ///
    /// 責務: 指定した由来・digest・水位を持つ同期記録を返します。
    /// - Parameters:
    ///   - sessionID: 対象の接続セッション。
    ///   - origin: 送信済みか復元済みか。
    ///   - digest: 記録する digest。
    ///   - watermark: 記録する水位。
    ///   - syncedAt: 同期した日時。
    /// - Returns: 同期記録。
    static func syncRecord(
        sessionID: ConnectionSessionID,
        origin: ConnectionSessionLocationTrackSyncOrigin,
        digest: String,
        watermark: ConnectionSessionLocationTrackWatermark,
        syncedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ConnectionSessionLocationTrackSyncRecord {
        ConnectionSessionLocationTrackSyncRecord(
            sessionID: sessionID,
            origin: origin,
            manifestDigest: digest,
            watermark: watermark,
            syncedAt: syncedAt
        )
    }

    /// 1文字を64回繰り返した digest 形式の文字列を作ります。
    ///
    /// 責務: SHA-256 の16進表記と同じ長さで、文字ごとに区別できる値を返します。
    /// - Parameter character: 繰り返す16進の1文字。
    /// - Returns: 64文字の文字列。
    static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    /// M件の状態変化を作ります。
    ///
    /// 責務: ordinal が 0 からの連番で、種類が全種類を巡回する状態変化を返します。
    /// - Parameter count: 件数。
    /// - Returns: ordinal 昇順の状態変化。
    private static func events(count: Int) -> [ConnectionSessionLocationEvent] {
        let kinds = ConnectionSessionLocationEventKind.allCases
        return (0..<count).map { ordinal in
            ConnectionSessionLocationEvent(
                ordinal: ordinal,
                occurredAt: Date(timeIntervalSince1970: eventReferenceSeconds + TimeInterval(ordinal)),
                kind: kinds[ordinal % kinds.count]
            )
        }
    }
}
