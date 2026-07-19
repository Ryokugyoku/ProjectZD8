/// 指定OBD終端へ接続して車両識別情報を取得する能力です。
protocol VehicleIdentificationPort: Sendable {
    /// 指定されたOBD接続終端から利用可能な識別情報を取得します。
    ///
    /// 責務: 1件のOBD終端に対する識別要求を改変しない観測結果として返します。
    /// - Parameter endpoint: ユーザーが選択したOBDアダプターの物理終端。
    /// - Returns: VIN候補と取得できた全表示可能フィールド。
    func identifyVehicle(using endpoint: OBDConnectionEndpoint) async throws -> VehicleIdentificationSnapshot
}
