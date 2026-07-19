/// 一次資料で数式まで確認できた標準PID定義を提供します。
enum StandardOBDPIDSeed {
    /// Elm Electronics ELM327DSHの説明で変換式まで確認できた定義です。
    static let definitions: [OBDPIDDefinition] = [
        OBDPIDDefinition(
            service: 0x01,
            pid: 0x05,
            nameKey: "obd.pid.engine_coolant_temperature",
            requiredByteCount: 1,
            formula: "A - 40",
            unit: "°C",
            minimumValue: -40,
            maximumValue: 215,
            sourceURI: "https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DSH.pdf#page=29",
            revision: 1
        ),
        OBDPIDDefinition(
            service: 0x01,
            pid: 0x0C,
            nameKey: "obd.pid.engine_speed",
            requiredByteCount: 2,
            formula: "(A * 256 + B) / 4",
            unit: "rpm",
            minimumValue: 0,
            maximumValue: 16_383.75,
            sourceURI: "https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DSH.pdf#page=29",
            revision: 1
        )
    ]

    /// 確認済み定義を改訂後退なしでリポジトリへ登録します。
    ///
    /// 責務: 現在バンドルする全標準PID定義を1件ずつ永続化します。
    /// - Parameter repository: 定義の保存先。
    /// - Throws: いずれかの定義を保存できない場合のリポジトリエラー。
    static func install(into repository: any OBDPIDDefinitionRepository) throws {
        for definition in definitions { try repository.upsert(definition) }
    }
}
