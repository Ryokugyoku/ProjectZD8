/// アプリに同梱するPID定義の一覧です。定義はコードで管理し、取得時点の内容をセッションへ複写します。
nonisolated enum OBDPIDCatalog {
    /// 指定車種で使える全定義(標準PIDと、その車種専用のPID)を返します。
    ///
    /// 責務: 車種コードに応じた同梱PID定義の一覧を返します。
    /// - Parameter vehicleModelCode: 車両の車種コード。不明な場合は `nil`。
    /// - Returns: 標準PIDに続けて車種専用PIDを並べた定義一覧。
    static func definitions(forVehicleModelCode vehicleModelCode: String?) -> [OBDPIDDefinition] {
        StandardOBDPIDCatalog.definitions
            + vehicleSpecificDefinitions.filter { $0.vehicleModelCode == vehicleModelCode }
    }

    /// 要求に一致する定義を返します。
    ///
    /// 責務: 1件のPID要求に対応する同梱定義を検索します。
    static func definition(for request: OBDPIDRequest, vehicleModelCode: String?) -> OBDPIDDefinition? {
        definitions(forVehicleModelCode: vehicleModelCode).first { $0.request == request }
    }

    /// 全車種の車種専用PID定義です。
    private static let vehicleSpecificDefinitions: [OBDPIDDefinition] = ZD8OBDPIDCatalog.definitions
}
