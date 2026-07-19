/// 一次資料で数式まで確認できた標準PID定義を提供します。
enum StandardOBDPIDSeed {
    /// SAE J1979DAで定義されるService 01からリアルタイム表示に適した主要50項目を選んだ定義です。
    static let definitions: [OBDPIDDefinition] = [
        definition(0x04, "calculated_engine_load", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x05, "engine_coolant_temperature", 1, "A - 40", "°C", -40, 215),
        definition(0x06, "short_term_fuel_trim_bank_1", 1, "(A - 128) * 100 / 128", "%", -100, 99.22),
        definition(0x07, "long_term_fuel_trim_bank_1", 1, "(A - 128) * 100 / 128", "%", -100, 99.22),
        definition(0x08, "short_term_fuel_trim_bank_2", 1, "(A - 128) * 100 / 128", "%", -100, 99.22),
        definition(0x09, "long_term_fuel_trim_bank_2", 1, "(A - 128) * 100 / 128", "%", -100, 99.22),
        definition(0x0A, "fuel_pressure", 1, "A * 3", "kPa", 0, 765),
        definition(0x0B, "intake_manifold_pressure", 1, "A", "kPa", 0, 255),
        definition(0x0C, "engine_speed", 2, "(A * 256 + B) / 4", "rpm", 0, 16_383.75),
        definition(0x0D, "vehicle_speed", 1, "A", "km/h", 0, 255),
        definition(0x0E, "timing_advance", 1, "A / 2 - 64", "°", -64, 63.5),
        definition(0x0F, "intake_air_temperature", 1, "A - 40", "°C", -40, 215),
        definition(0x10, "mass_air_flow_rate", 2, "(A * 256 + B) / 100", "g/s", 0, 655.35),
        definition(0x11, "absolute_throttle_position", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x14, "oxygen_sensor_b1s1_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x15, "oxygen_sensor_b1s2_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x16, "oxygen_sensor_b1s3_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x17, "oxygen_sensor_b1s4_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x18, "oxygen_sensor_b2s1_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x19, "oxygen_sensor_b2s2_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x1A, "oxygen_sensor_b2s3_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x1B, "oxygen_sensor_b2s4_voltage", 2, "A / 200", "V", 0, 1.275),
        definition(0x1F, "run_time_since_engine_start", 2, "A * 256 + B", "s", 0, 65_535),
        definition(0x21, "distance_with_mil_on", 2, "A * 256 + B", "km", 0, 65_535),
        definition(0x22, "fuel_rail_pressure_relative", 2, "(A * 256 + B) * 0.079", "kPa", 0, 5_177.265),
        definition(0x23, "fuel_rail_gauge_pressure", 2, "(A * 256 + B) * 10", "kPa", 0, 655_350),
        definition(0x2C, "commanded_egr", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x2D, "egr_error", 1, "(A - 128) * 100 / 128", "%", -100, 99.22),
        definition(0x2E, "commanded_evaporative_purge", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x2F, "fuel_tank_level", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x30, "warmups_since_codes_cleared", 1, "A", "count", 0, 255),
        definition(0x31, "distance_since_codes_cleared", 2, "A * 256 + B", "km", 0, 65_535),
        definition(0x32, "evap_system_vapor_pressure", 2, "(A * 256 + B) / 4 - 8192", "Pa", -8192, 8191.75),
        definition(0x33, "absolute_barometric_pressure", 1, "A", "kPa", 0, 255),
        definition(0x3C, "catalyst_temperature_b1s1", 2, "(A * 256 + B) / 10 - 40", "°C", -40, 6_513.5),
        definition(0x3D, "catalyst_temperature_b2s1", 2, "(A * 256 + B) / 10 - 40", "°C", -40, 6_513.5),
        definition(0x3E, "catalyst_temperature_b1s2", 2, "(A * 256 + B) / 10 - 40", "°C", -40, 6_513.5),
        definition(0x3F, "catalyst_temperature_b2s2", 2, "(A * 256 + B) / 10 - 40", "°C", -40, 6_513.5),
        definition(0x42, "control_module_voltage", 2, "(A * 256 + B) / 1000", "V", 0, 65.535),
        definition(0x43, "absolute_load_value", 2, "(A * 256 + B) * 100 / 255", "%", 0, 25_700),
        definition(0x44, "commanded_equivalence_ratio", 2, "(A * 256 + B) / 32768", "ratio", 0, 1.99997),
        definition(0x45, "relative_throttle_position", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x46, "ambient_air_temperature", 1, "A - 40", "°C", -40, 215),
        definition(0x47, "absolute_throttle_position_b", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x48, "absolute_throttle_position_c", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x49, "accelerator_pedal_position_d", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x4A, "accelerator_pedal_position_e", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x4B, "accelerator_pedal_position_f", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x4C, "commanded_throttle_actuator", 1, "A * 100 / 255", "%", 0, 100),
        definition(0x4D, "time_run_with_mil_on", 2, "A * 256 + B", "min", 0, 65_535)
    ]

    /// 現行Service 01定義の一次資料URIです。
    private static let sourceURI = "https://saemobilus.sae.org/standards/j1979da_202607-j1979-da-digital-annex-e-e-diagnostic-test-modes"

    /// 主要PIDの定型項目を1件の永続化定義へ変換します。
    ///
    /// 責務: Service 01の表示対象PIDを共通出典と改訂番号を持つ定義へ固定します。
    /// - Parameters:
    ///   - pid: Service 01内のPID番号。
    ///   - name: ローカライズキーの末尾。
    ///   - requiredByteCount: 数式評価に必要なバイト数。
    ///   - formula: 応答バイトへ適用する制限付き数式。
    ///   - unit: 計算結果の単位。
    ///   - minimumValue: 規格上の最小値。
    ///   - maximumValue: 規格上の最大値。
    /// - Returns: 永続化できるService 01 PID定義。
    private static func definition(
        _ pid: UInt8,
        _ name: String,
        _ requiredByteCount: Int,
        _ formula: String,
        _ unit: String,
        _ minimumValue: Double,
        _ maximumValue: Double
    ) -> OBDPIDDefinition {
        OBDPIDDefinition(
            service: 0x01,
            pid: pid,
            nameKey: "obd.pid.\(name)",
            requiredByteCount: requiredByteCount,
            formula: formula,
            unit: unit,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            sourceURI: sourceURI,
            revision: 1
        )
    }

    /// 確認済み定義を改訂後退なしでリポジトリへ登録します。
    ///
    /// 責務: 現在バンドルする全標準PID定義を1件ずつ永続化します。
    /// - Parameter repository: 定義の保存先。
    /// - Throws: いずれかの定義を保存できない場合のリポジトリエラー。
    static func install(into repository: any OBDPIDDefinitionRepository) throws {
        for definition in definitions { try repository.upsert(definition) }
    }
}
