import Foundation

/// ボリュームの空き容量を返す `RoadRegulationStorageCapacityPort` の実装です。
nonisolated struct VolumeRoadRegulationStorageCapacityAdapter: RoadRegulationStorageCapacityPort {
    private let volumeURL: URL

    /// 容量を調べるボリュームを指定して作ります。
    ///
    /// 責務: 調べる場所(ボリューム上の URL)を保持します。
    /// - Parameter volumeURL: 調べるボリューム上のファイルまたはフォルダの URL。
    init(volumeURL: URL) {
        self.volumeURL = volumeURL
    }

    /// 取得と取り込みに使える空き容量を返します。
    ///
    /// 責務: `volumeAvailableCapacityForImportantUsageKey` の値を返し、無ければ通常の空き容量で代えます。
    /// - Returns: 空き容量(バイト)。
    /// - Throws: どちらも読めない時は `RoadRegulationImportError.storageUnavailable`。
    func availableCapacityBytes() throws -> Int64 {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? volumeURL.resourceValues(forKeys: keys) else {
            throw RoadRegulationImportError.storageUnavailable
        }
        if let important = values.volumeAvailableCapacityForImportantUsage { return important }
        if let plain = values.volumeAvailableCapacity { return Int64(plain) }
        throw RoadRegulationImportError.storageUnavailable
    }
}
