import Foundation
@testable import ProjectZD8

/// 事前に用意したリンクを返す `OBDLinkPort` です。
final class DriveFlowLinkPort: OBDLinkPort, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<any OBDLink, OBDLinkError>
    private var opened: [AdapterDescriptor] = []

    init(link: any OBDLink) { result = .success(link) }
    init(error: OBDLinkError) { result = .failure(error) }

    func open(_ adapter: AdapterDescriptor) async throws -> any OBDLink {
        lock.withLock { opened.append(adapter) }
        await Task.yield()
        return try result.get()
    }

    var openedAdapters: [AdapterDescriptor] { lock.withLock { opened } }
}

/// 呼び出しを記録する `SleepInhibitingPort` です。
@MainActor
final class DriveFlowSleepInhibitor: SleepInhibitingPort {
    private(set) var calls: [Bool] = []
    func setInhibited(_ isInhibited: Bool) { calls.append(isInhibited) }
}

/// 固定の実行環境を返す `AcquisitionEnvironmentPort` です。
struct DriveFlowEnvironment: AcquisitionEnvironmentPort {
    func environment() -> AcquisitionEnvironment {
        AcquisitionEnvironment(appVersion: "1.0", appBuild: "7", platform: .mac, deviceID: "device-1", deviceName: "Test Mac")
    }
}

/// 配信された取得の出来事を溜める `AcquisitionEventPublishing` です。
@MainActor
final class DriveFlowEventRecorder: AcquisitionEventPublishing {
    private(set) var events: [AcquisitionEvent] = []
    func publish(_ event: AcquisitionEvent) { events.append(event) }
}

/// 探索結果を台本で返す `AdapterDiscoveryPort` です。`gate` を渡すと解放されるまで待ちます。
final class DriveFlowDiscoveryPort: AdapterDiscoveryPort, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[AdapterDescriptor], AdapterDiscoveryError>]
    private var gates: [AsyncStream<Void>.Continuation] = []
    private var gateStreams: [AsyncStream<Void>]
    private var calls = 0

    /// - Parameter results: 呼び出し順の結果。
    /// - Parameter gated: `true` なら各呼び出しは `release(call:)` まで待ちます。
    init(results: [Result<[AdapterDescriptor], AdapterDiscoveryError>], gated: Bool = false) {
        self.results = results
        var streams: [AsyncStream<Void>] = []
        if gated {
            for _ in results {
                let (stream, continuation) = AsyncStream<Void>.makeStream()
                streams.append(stream)
                gates.append(continuation)
            }
        }
        gateStreams = streams
    }

    func discoverAdapters() async throws -> [AdapterDescriptor] {
        let (index, stream) = lock.withLock { () -> (Int, AsyncStream<Void>?) in
            defer { calls += 1 }
            return (calls, calls < gateStreams.count ? gateStreams[calls] : nil)
        }
        if let stream { for await _ in stream { break } }
        return try results[min(index, results.count - 1)].get()
    }

    func release(call: Int) { _ = lock.withLock { gates[call].yield() } }
    var callCount: Int { lock.withLock { calls } }
}

/// メモリ上の `DefaultAdapterStorePort` です。
final class DriveFlowDefaultAdapterStore: DefaultAdapterStorePort, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AdapterDescriptor?

    init(_ value: AdapterDescriptor? = nil) { self.value = value }

    func load() -> AdapterDescriptor? { lock.withLock { value } }
    func save(_ adapter: AdapterDescriptor?) { lock.withLock { value = adapter } }
}
