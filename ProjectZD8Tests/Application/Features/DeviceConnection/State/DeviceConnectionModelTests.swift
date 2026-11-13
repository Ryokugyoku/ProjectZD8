import XCTest
@testable import ProjectZD8

@MainActor
final class DeviceConnectionModelTests: XCTestCase {
    private typealias F = DriveFlowFixtures

    private let adapterA = AdapterDescriptor(transport: .bluetoothLowEnergy, systemIdentifier: "A", displayName: "A")
    private let adapterB = AdapterDescriptor(transport: .usbSerial, systemIdentifier: "/dev/B", displayName: "B")
    private let demo = AdapterDescriptor(transport: .demo, systemIdentifier: "demo", displayName: "Demo")

    private func makeModel(
        discovery: DriveFlowDiscoveryPort, store: DriveFlowDefaultAdapterStore = DriveFlowDefaultAdapterStore(),
        demoEnabled: Bool = false, onConnect: @escaping @MainActor (AdapterDescriptor) -> Void = { _ in }
    ) -> DeviceConnectionModel {
        DeviceConnectionModel(
            discovery: discovery, defaultStore: store, isDemoModeEnabled: { demoEnabled }, demoAdapter: demo,
            connectRequested: onConnect
        )
    }

    func testLoadsStoredDefaultAdapterOnInit() {
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([])]), store: DriveFlowDefaultAdapterStore(adapterA))
        XCTAssertEqual(model.state.defaultAdapter, adapterA)
        XCTAssertFalse(model.state.isDefaultAdapterDetected)
    }

    func testDiscoveryPublishesAdaptersAndDetectsTheDefault() async {
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([adapterA, adapterB])]), store: DriveFlowDefaultAdapterStore(adapterB))
        model.send(.discoverRequested)
        XCTAssertEqual(model.state.discovery, .discovering)
        let done = await F.waitUntil { model.state.discovery == .completed }
        XCTAssertTrue(done)
        XCTAssertEqual(model.state.adapters, [adapterA, adapterB])
        XCTAssertTrue(model.state.isDefaultAdapterDetected)
    }

    func testDefaultNotDetectedWhenAbsentFromResults() async {
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([adapterA])]), store: DriveFlowDefaultAdapterStore(adapterB))
        model.send(.discoverRequested)
        _ = await F.waitUntil { model.state.discovery == .completed }
        XCTAssertFalse(model.state.isDefaultAdapterDetected)
    }

    func testDemoAdapterIsAppendedOnlyInDemoMode() async {
        let on = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([adapterA])]), demoEnabled: true)
        on.send(.discoverRequested)
        _ = await F.waitUntil { on.state.discovery == .completed }
        XCTAssertEqual(on.state.adapters, [adapterA, demo])

        let off = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([adapterA])]), demoEnabled: false)
        off.send(.discoverRequested)
        _ = await F.waitUntil { off.state.discovery == .completed }
        XCTAssertEqual(off.state.adapters, [adapterA])
    }

    func testDemoAdapterCanBeTheDetectedDefault() async {
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([])]), store: DriveFlowDefaultAdapterStore(demo), demoEnabled: true)
        model.send(.discoverRequested)
        _ = await F.waitUntil { model.state.discovery == .completed }
        XCTAssertTrue(model.state.isDefaultAdapterDetected)
    }

    func testTypedFailureIsSurfacedAndDemoAdapterStillOffered() async {
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.failure(.bluetoothPoweredOff)]), demoEnabled: true)
        model.send(.discoverRequested)
        let done = await F.waitUntil { model.state.discovery != .discovering }
        XCTAssertTrue(done)
        XCTAssertEqual(model.state.discovery, .failed(.bluetoothPoweredOff))
        XCTAssertEqual(model.state.adapters, [demo])
    }

    func testOnlyOneDiscoveryIsInFlight() async {
        let port = DriveFlowDiscoveryPort(results: [.success([adapterA])], gated: true)
        let model = makeModel(discovery: port)
        model.send(.discoverRequested)
        model.send(.discoverRequested)
        _ = await F.waitUntil { port.callCount == 1 }
        port.release(call: 0)
        let done = await F.waitUntil { model.state.discovery == .completed }
        XCTAssertTrue(done)
        XCTAssertEqual(port.callCount, 1)
    }

    func testCancelledDiscoveryResultIsDropped() async {
        let port = DriveFlowDiscoveryPort(results: [.success([adapterA]), .success([adapterB])], gated: true)
        let model = makeModel(discovery: port)
        model.send(.discoverRequested)
        _ = await F.waitUntil { port.callCount == 1 }
        model.send(.discoveryCancelled)
        XCTAssertEqual(model.state.discovery, .idle)
        model.send(.discoverRequested)
        _ = await F.waitUntil { port.callCount == 2 }

        port.release(call: 0)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.state.discovery, .discovering, "the stale result must not complete the new discovery")
        XCTAssertEqual(model.state.adapters, [])

        port.release(call: 1)
        let done = await F.waitUntil { model.state.discovery == .completed }
        XCTAssertTrue(done)
        XCTAssertEqual(model.state.adapters, [adapterB])
    }

    func testSelectingAndClearingTheDefaultAdapterPersists() async {
        let store = DriveFlowDefaultAdapterStore()
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([adapterA])]), store: store)
        model.send(.discoverRequested)
        _ = await F.waitUntil { model.state.discovery == .completed }

        model.send(.defaultAdapterSelected(adapterA))
        XCTAssertEqual(store.load(), adapterA)
        XCTAssertEqual(model.state.defaultAdapter, adapterA)
        XCTAssertTrue(model.state.isDefaultAdapterDetected)

        model.send(.defaultAdapterCleared)
        XCTAssertNil(store.load())
        XCTAssertNil(model.state.defaultAdapter)
        XCTAssertFalse(model.state.isDefaultAdapterDetected)
    }

    func testReloadPicksUpExternallyChangedDefault() {
        let store = DriveFlowDefaultAdapterStore()
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([])]), store: store)
        store.save(adapterB)
        model.send(.defaultAdapterLoadRequested)
        XCTAssertEqual(model.state.defaultAdapter, adapterB)
    }

    func testAcceptedArrivalIsForwardedAsConnectRequest() {
        var forwarded: [AdapterDescriptor] = []
        let model = makeModel(discovery: DriveFlowDiscoveryPort(results: [.success([])])) { forwarded.append($0) }
        model.acceptArrival(adapterA)
        XCTAssertEqual(forwarded, [adapterA])
    }
}
