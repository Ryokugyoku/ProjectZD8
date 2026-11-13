import Foundation
@testable import ProjectZD8

/// 固定の結果を返す、テスト用の `AdapterDiscoveryPort` です。
struct DevicesFakeAdapterDiscovery: AdapterDiscoveryPort {
    /// 返す結果です。
    let result: Result<[AdapterDescriptor], AdapterDiscoveryError>

    /// 責務: 固定の結果を持つ探索を生成します。
    init(_ result: Result<[AdapterDescriptor], AdapterDiscoveryError>) {
        self.result = result
    }

    /// 責務: 固定の結果を返す、または投げます。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        try result.get()
    }
}
