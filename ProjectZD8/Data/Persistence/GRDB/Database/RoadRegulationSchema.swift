import GRDB

/// 交通規制データの版・拒否件数・規制・升目の索引の表を定義します。
nonisolated enum RoadRegulationSchema {
    /// 交通規制データの表と索引を追加します。
    ///
    /// 責務: 既存の行を変更せず、版の表(県ごとに active と importing を1つまで)、拒否件数の表、
    /// 規制の表、升目の索引の表を追加します。子の表は版の削除で連動して消えます。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    static func create(in database: Database) throws {
        try createDatasets(in: database)
        try createRejections(in: database)
        try createRegulations(in: database)
        try createCells(in: database)
    }

    /// 版の表と、県ごとの一意索引を追加します。
    ///
    /// 責務: active の版に必要な欄が揃っていることを CHECK で守り、県ごとの active と importing を1つまでにします。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createDatasets(in database: Database) throws {
        let states = quotedList(RoadRegulationDatasetState.allCases.map(\.rawValue))
        try database.execute(sql: """
            CREATE TABLE road_regulation_datasets (
                id TEXT PRIMARY KEY NOT NULL,
                prefectureCode INTEGER NOT NULL CHECK (prefectureCode BETWEEN 1 AND 47),
                state TEXT NOT NULL CHECK (state IN (\(states))),
                publicationStamp TEXT NOT NULL CHECK (length(publicationStamp) = 12),
                sourceURL TEXT NOT NULL,
                downloadedAtMicroseconds INTEGER NOT NULL,
                activatedAtMicroseconds INTEGER,
                dataYear INTEGER CHECK (dataYear IS NULL OR dataYear BETWEEN 2000 AND 2999),
                dataMonth INTEGER CHECK (dataMonth IS NULL OR dataMonth BETWEEN 1 AND 12),
                formatVersion TEXT,
                totalRowCount INTEGER NOT NULL DEFAULT 0 CHECK (totalRowCount >= 0),
                importedCount INTEGER NOT NULL DEFAULT 0 CHECK (importedCount >= 0),
                skippedOutOfScopeCount INTEGER NOT NULL DEFAULT 0 CHECK (skippedOutOfScopeCount >= 0),
                skippedAbolishedCount INTEGER NOT NULL DEFAULT 0 CHECK (skippedAbolishedCount >= 0),
                coverageMinLatitude REAL,
                coverageMaxLatitude REAL,
                coverageMinLongitude REAL,
                coverageMaxLongitude REAL,
                CHECK (state <> 'active' OR (
                    activatedAtMicroseconds IS NOT NULL AND dataYear IS NOT NULL AND dataMonth IS NOT NULL
                    AND formatVersion IS NOT NULL
                    AND coverageMinLatitude IS NOT NULL AND coverageMaxLatitude IS NOT NULL
                    AND coverageMinLongitude IS NOT NULL AND coverageMaxLongitude IS NOT NULL
                ))
            );
            CREATE UNIQUE INDEX road_regulation_datasets_one_active
                ON road_regulation_datasets(prefectureCode) WHERE state = 'active';
            CREATE UNIQUE INDEX road_regulation_datasets_one_importing
                ON road_regulation_datasets(prefectureCode) WHERE state = 'importing';
            """)
    }

    /// 版ごとの拒否件数の表を追加します。
    ///
    /// 責務: 拒否理由を既知の値に限り、件数を正の値に限ります。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createRejections(in database: Database) throws {
        let reasons = quotedList(RoadRegulationRowRejection.allCases.map(\.rawValue))
        try database.execute(sql: """
            CREATE TABLE road_regulation_dataset_rejections (
                datasetID TEXT NOT NULL REFERENCES road_regulation_datasets(id) ON DELETE CASCADE,
                reason TEXT NOT NULL CHECK (reason IN (\(reasons))),
                count INTEGER NOT NULL CHECK (count > 0),
                PRIMARY KEY (datasetID, reason)
            ) WITHOUT ROWID;
            """)
    }

    /// 規制の表を追加します。
    ///
    /// 責務: 種別と速度・一方通行の並びの組を CHECK で守り、版の中のユニークキーを一意にします。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createRegulations(in database: Database) throws {
        let kinds = quotedList(RoadRegulationKind.allCases.map(\.rawValue))
        try database.execute(sql: """
            CREATE TABLE road_regulations (
                id INTEGER PRIMARY KEY,
                datasetID TEXT NOT NULL REFERENCES road_regulation_datasets(id) ON DELETE CASCADE,
                uniqueKey TEXT NOT NULL CHECK (length(uniqueKey) BETWEEN 1 AND 64),
                kind TEXT NOT NULL CHECK (kind IN (\(kinds))),
                speedLimitKph INTEGER CHECK (speedLimitKph IS NULL OR speedLimitKph BETWEEN 1 AND 120),
                sideCode INTEGER CHECK (sideCode IS NULL OR sideCode IN (1, 2, 3)),
                oneWayOrder INTEGER CHECK (oneWayOrder IS NULL OR oneWayOrder IN (1, 2)),
                perimeterRoadIncluded INTEGER CHECK (perimeterRoadIncluded IS NULL OR perimeterRoadIncluded IN (0, 1)),
                conditions TEXT,
                geometry BLOB NOT NULL CHECK (length(geometry) >= 3),
                CHECK ((kind IN ('speedLimitSection', 'speedLimitZone')) = (speedLimitKph IS NOT NULL)),
                CHECK ((kind = 'oneWay') = (oneWayOrder IS NOT NULL)),
                UNIQUE (datasetID, uniqueKey)
            );
            """)
    }

    /// 升目の索引の表を追加します。
    ///
    /// 責務: (版, 升目, 規制) を主キーにして検索の索引を兼ねます。規制の行への外部キーは付けず、整合は Repository が守ります。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createCells(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE road_regulation_cells (
                datasetID TEXT NOT NULL REFERENCES road_regulation_datasets(id) ON DELETE CASCADE,
                cellKey INTEGER NOT NULL,
                regulationID INTEGER NOT NULL,
                PRIMARY KEY (datasetID, cellKey, regulationID)
            ) WITHOUT ROWID;
            """)
    }

    /// 文字列の一覧を SQL の IN 句の中身にします。
    ///
    /// 責務: 各値を単一引用符で囲み、カンマで連結します(値は列挙型の rawValue に限る)。
    /// - Parameter values: 囲む値。
    /// - Returns: `'a', 'b'` の形の文字列。
    private static func quotedList(_ values: [String]) -> String {
        values.map { "'\($0)'" }.joined(separator: ", ")
    }
}
