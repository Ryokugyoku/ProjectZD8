import Foundation
import XCTest
@testable import ProjectZD8

/// 軌跡まわりのテストが共有する、位置・事象・軌跡・水位・同期記録の値生成です。
enum ConnectionSessionLocationTrackValueFixtures {
    /// 64文字の16進に見えるダイジェストを返します。
    ///
    /// 責務: 同期記録のダイジェスト長の制約(64文字)を満たす固定の文字列を返します。
    /// - Parameter character: 64回繰り返す1文字。
    /// - Returns: 64文字のダイジェスト。
    static func digest(_ character: Character = "a") -> String {
        String(repeating: character, count: 64)
    }

    /// 添字ごとに値が変わり、奇数番目は任意項目をすべて持たない位置を返します。
    ///
    /// 責務: マイクロ秒で正確に表せる時刻と、任意項目の有無が混ざった位置を決定的に作ります。
    /// - Parameter index: 値を変える添字。
    /// - Returns: 不変条件を満たす位置。
    /// - Throws: 生成できない場合の `XCTUnwrap` 失敗。
    static func fix(_ index: Int) throws -> LocationFix {
        let hasOptionals = index % 2 == 0
        return try XCTUnwrap(
            LocationFix(
                latitude: 35 + Double(index) * 0.25,
                longitude: 139 + Double(index) * 0.5,
                altitudeMeters: hasOptionals ? 10 + Double(index) : nil,
                horizontalAccuracyMeters: 4.5 + Double(index),
                verticalAccuracyMeters: hasOptionals ? 3.25 : nil,
                speedMetersPerSecond: hasOptionals ? 8.75 : nil,
                courseDegrees: hasOptionals ? 270.5 : nil,
                observedAt: Date(timeIntervalSince1970: 2_000.5 + Double(index)),
                monotonicNanoseconds: UInt64(index) * 1_000_000_007
            )
        )
    }

    /// 指定した sequence を持つ位置の列を返します。
    ///
    /// 責務: 歯抜けの番号も含めて、渡した番号どおりのサンプルを作ります。
    /// - Parameter sequences: 各サンプルの sequence。
    /// - Returns: 渡した順のサンプル。
    /// - Throws: 位置の生成失敗。
    static func samples(_ sequences: [Int64]) throws -> [ConnectionSessionLocationSample] {
        try sequences.enumerated().map { ConnectionSessionLocationSample(sequence: $0.element, fix: try fix($0.offset)) }
    }

    /// 指定した ordinal を持つ事象の列を返します。
    ///
    /// 責務: 種類が全種類を巡回する、渡した番号どおりの事象を作ります。
    /// - Parameter ordinals: 各事象の ordinal。
    /// - Returns: 渡した順の事象。
    static func events(_ ordinals: [Int]) -> [ConnectionSessionLocationEvent] {
        let kinds = ConnectionSessionLocationEventKind.allCases
        return ordinals.enumerated().map {
            ConnectionSessionLocationEvent(
                ordinal: $0.element,
                occurredAt: Date(timeIntervalSince1970: 3_000.25 + Double($0.offset)),
                kind: kinds[$0.offset % kinds.count]
            )
        }
    }

    /// 指定した番号の軌跡を返します。
    ///
    /// 責務: サンプルと事象の番号を渡して1セッション分の軌跡を作ります。
    /// - Parameters:
    ///   - sessionID: 軌跡のセッションID。
    ///   - sampleSequences: サンプルの sequence。
    ///   - eventOrdinals: 事象の ordinal。
    /// - Returns: 軌跡。
    /// - Throws: 位置の生成失敗。
    static func track(
        _ sessionID: ConnectionSessionID,
        sampleSequences: [Int64] = [],
        eventOrdinals: [Int] = []
    ) throws -> ConnectionSessionLocationTrack {
        ConnectionSessionLocationTrack(
            sessionID: sessionID,
            samples: try samples(sampleSequences),
            events: events(eventOrdinals)
        )
    }

    /// 水位を返します。
    ///
    /// 責務: 4項目を省略可能な既定値つきで組み立てます。
    /// - Parameters:
    ///   - sampleCount: サンプル件数。
    ///   - lastSampleSequence: 最終 sequence。
    ///   - eventCount: 事象件数。
    ///   - lastEventOrdinal: 最終 ordinal。
    /// - Returns: 水位。
    static func watermark(
        _ sampleCount: Int,
        _ lastSampleSequence: Int64?,
        _ eventCount: Int,
        _ lastEventOrdinal: Int?
    ) -> ConnectionSessionLocationTrackWatermark {
        ConnectionSessionLocationTrackWatermark(
            sampleCount: sampleCount,
            lastSampleSequence: lastSampleSequence,
            eventCount: eventCount,
            lastEventOrdinal: lastEventOrdinal
        )
    }

    /// 連番(0 始まり)でサンプル `sampleCount` 件・事象 `eventCount` 件の水位を返します。
    ///
    /// 責務: 追記だけで作った軌跡に対する期待水位(件数と最大番号)を仕様から導きます。
    /// - Parameters:
    ///   - samples: サンプル件数。
    ///   - events: 事象件数。
    /// - Returns: 0 件なら最終番号が `nil` の水位。
    static func contiguousWatermark(samples: Int, events: Int) -> ConnectionSessionLocationTrackWatermark {
        watermark(samples, samples > 0 ? Int64(samples - 1) : nil, events, events > 0 ? events - 1 : nil)
    }

    /// 同期記録を返します。
    ///
    /// 責務: 既定値つきで1件の同期記録を組み立てます。
    /// - Parameters:
    ///   - sessionID: セッションID。
    ///   - origin: 由来。
    ///   - digest: ダイジェスト。
    ///   - watermark: 水位。
    ///   - syncedAt: 同期日時(マイクロ秒で正確に表せる値)。
    /// - Returns: 同期記録。
    static func syncRecord(
        _ sessionID: ConnectionSessionID,
        origin: ConnectionSessionLocationTrackSyncOrigin = .uploaded,
        digest: String = digest(),
        watermark: ConnectionSessionLocationTrackWatermark,
        syncedAt: Date = Date(timeIntervalSince1970: 5_000.25)
    ) -> ConnectionSessionLocationTrackSyncRecord {
        ConnectionSessionLocationTrackSyncRecord(
            sessionID: sessionID,
            origin: origin,
            manifestDigest: digest,
            watermark: watermark,
            syncedAt: syncedAt
        )
    }
}
