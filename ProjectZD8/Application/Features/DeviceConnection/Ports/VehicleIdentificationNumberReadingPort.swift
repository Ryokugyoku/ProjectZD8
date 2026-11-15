/// 応答した車両からVINを読み取る能力です。
@MainActor
protocol VehicleIdentificationNumberReadingPort: AnyObject {
    /// 車両のVINを読み取ります。
    ///
    /// 責務: 1回の問い合わせで車両のVINを読み取ります。
    /// - Returns: 読み取ったVIN。車両がVINを返さない・解釈できない場合は `nil`。
    /// - Throws: 送受信の失敗・キャンセルなど、読取を完了できなかった場合のエラー。
    func readVehicleIdentificationNumber() async throws -> String?
}
