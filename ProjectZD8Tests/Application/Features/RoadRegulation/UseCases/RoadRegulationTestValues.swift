import Foundation
@testable import ProjectZD8

/// 交通規制の取り込み・設定のテストが共有する値を作る補助です。形状は基準点からのメートル単位の位置で作ります。架空の座標だけを使います。
nonisolated enum RoadRegulationTestValues {
    /// 形状の基準点(沖縄の近くの架空の点)です。
    static let origin = coordinate(latitude: 26.2, longitude: 127.7)
    /// テストで使う固定の時刻です。
    static let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)
    /// 一覧の公開の印の既定値です。
    static let publicationStamp = "202611010000"
    /// 一覧の基準月の既定値(2026年9月)です。
    static let catalogMonth = month(2026, 9)

    /// 責務: 都道府県コードを作ります(範囲外ならテストの誤り)。
    static func prefecture(_ number: Int) -> JapanesePrefectureCode {
        guard let code = JapanesePrefectureCode(number) else { preconditionFailure("テスト用の都道府県コードが範囲外です") }
        return code
    }

    /// 責務: 座標を作ります(範囲外ならテストの誤り)。
    static func coordinate(latitude: Double, longitude: Double) -> GeoCoordinate {
        guard let value = GeoCoordinate(latitude: latitude, longitude: longitude) else { preconditionFailure("テスト用の座標が範囲外です") }
        return value
    }

    /// 責務: 基準点から東へ `east` m、北へ `north` m の座標を作ります。
    static func offset(east: Double, north: Double, from base: GeoCoordinate = origin) -> GeoCoordinate {
        guard let value = GeoLocalProjection(origin: base).unproject(GeoPlanarPoint(x: east, y: north)) else {
            preconditionFailure("テスト用の位置を座標にできません")
        }
        return value
    }

    /// 責務: 基準月を作ります(範囲外ならテストの誤り)。
    static func month(_ year: Int, _ month: Int) -> RoadRegulationDataMonth {
        guard let value = RoadRegulationDataMonth(year: year, month: month) else { preconditionFailure("テスト用の基準月が範囲外です") }
        return value
    }

    /// 責務: 外接矩形を作ります(不正ならテストの誤り)。
    static func box(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) -> GeoBoundingBox {
        guard let value = GeoBoundingBox(
            minLatitude: minLatitude, maxLatitude: maxLatitude, minLongitude: minLongitude, maxLongitude: maxLongitude
        ) else { preconditionFailure("テスト用の外接矩形が不正です") }
        return value
    }

    /// 責務: 最高速度(区間)の線の下書きを、指定の点列で作ります。
    static func lineDraft(_ key: String, points: [GeoCoordinate], speedLimitKph: Int = 40) -> RoadRegulationDraft {
        draft(key, kind: .speedLimitSection, speed: speedLimitKph, parts: [RoadRegulationGeometryPart(role: .main, coordinates: points)])
    }

    /// 責務: 基準点から東へ `lengthMeters` m 進む、最高速度(区間)の線の下書きを作ります。
    static func eastwardLineDraft(_ key: String, from base: GeoCoordinate = origin, lengthMeters: Double = 300) -> RoadRegulationDraft {
        lineDraft(key, points: [base, offset(east: lengthMeters, north: 0, from: base)])
    }

    /// 責務: 一時停止の下書き(停止点と、北へ `approachMeters` m の進入方向の点)を作ります。
    static func stopDraft(_ key: String, at stop: GeoCoordinate = origin, approachMeters: Double = 15) -> RoadRegulationDraft {
        draft(key, kind: .stop, speed: nil, parts: [
            RoadRegulationGeometryPart(role: .main, coordinates: [stop]),
            RoadRegulationGeometryPart(role: .approach, coordinates: [offset(east: 0, north: approachMeters, from: stop)]),
        ])
    }

    /// 責務: 一辺 `sideMeters` m の正方形の最高速度(区域)の下書き(閉じた輪)を作ります。
    static func areaDraft(_ key: String, southWest: GeoCoordinate = origin, sideMeters: Double) -> RoadRegulationDraft {
        let ring = [
            southWest,
            offset(east: sideMeters, north: 0, from: southWest),
            offset(east: sideMeters, north: sideMeters, from: southWest),
            offset(east: 0, north: sideMeters, from: southWest),
            southWest,
        ]
        return draft(key, kind: .speedLimitZone, speed: 30, parts: [RoadRegulationGeometryPart(role: .main, coordinates: ring)])
    }

    /// 責務: 外接矩形が 10,000 升を超える(緯度経度とも1度の)面の下書きを作ります。
    static func oversizedAreaDraft(_ key: String) -> RoadRegulationDraft {
        let ring = [
            coordinate(latitude: 26.0, longitude: 127.0),
            coordinate(latitude: 26.0, longitude: 128.0),
            coordinate(latitude: 27.0, longitude: 128.0),
            coordinate(latitude: 27.0, longitude: 127.0),
            coordinate(latitude: 26.0, longitude: 127.0),
        ]
        return draft(key, kind: .speedLimitZone, speed: 30, parts: [RoadRegulationGeometryPart(role: .main, coordinates: ring)])
    }

    /// 責務: 一覧の1行を作ります。
    static func catalogEntry(_ prefecture: JapanesePrefectureCode, stamp: String = publicationStamp) -> RoadRegulationCatalogEntry {
        RoadRegulationCatalogEntry(prefecture: prefecture, archiveURL: archiveURL(prefecture, stamp: stamp), publicationStamp: stamp)
    }

    /// 責務: 指定の県の行を持つ一覧を作ります。
    static func catalog(
        _ prefectures: [JapanesePrefectureCode],
        stamp: String = publicationStamp,
        dataMonth: RoadRegulationDataMonth? = catalogMonth
    ) -> RoadRegulationCatalog {
        RoadRegulationCatalog(dataMonth: dataMonth, entries: prefectures.map { catalogEntry($0, stamp: stamp) })
    }

    /// 責務: 一覧の行の ZIP の URL(架空)を作ります。
    static func archiveURL(_ prefecture: JapanesePrefectureCode, stamp: String = publicationStamp) -> URL {
        guard let url = URL(string: "https://www.jartic.or.jp/d/opendata/\(stamp)/typeD_p\(prefecture.twoDigitText).zip") else {
            preconditionFailure("テスト用の URL を作れません")
        }
        return url
    }

    /// 責務: 取り込みの件数を作ります。
    static func counts(totalRows: Int = 10, imported: Int = 8, rejected: [RoadRegulationRowRejection: Int] = [.invalidSpeed: 1])
        -> RoadRegulationImportCounts {
        RoadRegulationImportCounts(
            totalRows: totalRows, importedRegulations: imported, skippedOutOfScope: 1, skippedAbolished: 0, rejectedByReason: rejected
        )
    }

    /// 責務: 有効な版の値を作ります。
    static func dataset(
        _ prefecture: JapanesePrefectureCode,
        month dataMonth: RoadRegulationDataMonth = month(2026, 8),
        stamp: String = "202610010000",
        downloadedAt: Date = fixedNow.addingTimeInterval(-86_400)
    ) -> RoadRegulationDataset {
        RoadRegulationDataset(
            id: RoadRegulationDatasetID(rawValue: UUID()), prefecture: prefecture, state: .active, dataMonth: dataMonth,
            publicationStamp: stamp, sourceURL: archiveURL(prefecture, stamp: stamp), downloadedAt: downloadedAt,
            activatedAt: downloadedAt, formatVersion: "k_2.1", counts: counts(),
            coverage: box(minLatitude: 26.0, maxLatitude: 26.5, minLongitude: 127.5, maxLongitude: 128.0)
        )
    }

    /// 責務: 下書きを作ります。
    private static func draft(
        _ key: String,
        kind: RoadRegulationKind,
        speed: Int?,
        parts: [RoadRegulationGeometryPart]
    ) -> RoadRegulationDraft {
        RoadRegulationDraft(
            uniqueKey: key, kind: kind, speedLimitKph: speed, side: nil, oneWayOrder: nil, perimeterRoadIncluded: nil,
            conditions: .unconditional, geometry: RoadRegulationGeometry(parts: parts)
        )
    }
}
