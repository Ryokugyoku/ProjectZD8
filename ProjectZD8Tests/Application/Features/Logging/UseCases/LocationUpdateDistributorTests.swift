import XCTest
@testable import ProjectZD8

/// `LocationUpdateDistributor` が1か所の位置の流れを購読者へ配り、購読者の有無で取得を始め・止めることを検証します。
@MainActor
final class LocationUpdateDistributorTests: XCTestCase {
    /// 位置の取得元の fake です。
    private var source: LocationUpdateSourceFake!
    /// テストで作った購読の読み手です(後始末で取消します)。
    private var collectors: [LocationUpdateDistributorEventCollector] = []

    /// 取得元の fake につながった配布役を作ります。
    ///
    /// 責務: 呼出回数 0 の取得元と、それを読む配布役を組み立てます。
    /// - Returns: テスト対象の配布役。
    private func makeDistributor() -> LocationUpdateDistributor {
        source = LocationUpdateSourceFake()
        return LocationUpdateDistributor(source: source)
    }

    /// 購読して読み始めます。
    ///
    /// 責務: 配布役の流れを購読し、受け取った事象を記録する読み手を返します。
    /// - Parameter distributor: 購読先の配布役。
    /// - Returns: 読み手。
    private func startReading(_ distributor: LocationUpdateDistributor) -> LocationUpdateDistributorEventCollector {
        let collector = LocationUpdateDistributorEventCollector(stream: distributor.subscribe())
        collectors.append(collector)
        return collector
    }

    /// 残った読み手と流れを後始末します。
    ///
    /// 責務: 実装が流れを終えなかった場合でも、読み手のタスクを取消して止めます。
    override func tearDown() async throws {
        collectors.forEach { $0.cancel() }
        collectors = []
        source?.finishAll()
        source = nil
        try await super.tearDown()
    }

    /// 購読者がいない間は取得元の流れを作りません。
    ///
    /// 責務: 生成しただけでは `makeUpdates()` が呼ばれず、購読者数が 0 であることを確認します。
    func testDoesNotStartSourceWithoutSubscribers() async {
        let distributor = makeDistributor()
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(source.makeUpdatesCallCount, 0)
        XCTAssertEqual(distributor.subscriberCount, 0)
    }

    /// 最初の購読を読み始めると取得元の流れを1回だけ作り、事象を届けます。
    ///
    /// 責務: 0→1 で `makeUpdates()` が1回呼ばれ、流した事象が購読者へ届くことを確認します。
    func testFirstSubscriberStartsSourceOnce() async throws {
        let distributor = makeDistributor()
        let reader = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount == 1 }
        let fix = try ConnectionSessionLocationTestValues.fix(index: 1)
        source.yield(.fix(fix))
        await LocationRecordingBoundedWaiter.waitUntil("購読者へ届く") { reader.events == [.fix(fix)] }
        XCTAssertEqual(source.makeUpdatesCallCount, 1)
    }

    /// 2人の購読者へ同じ事象が同じ順で届き、取得元の流れは1つのままです。
    ///
    /// 責務: 位置と取得不可の事象が両方の購読者へ同順で届き、`makeUpdates()` が1回であることを確認します。
    func testTwoSubscribersReceiveSameEventsInOrder() async throws {
        let distributor = makeDistributor()
        let first = startReading(distributor)
        let second = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("2人が購読する") { distributor.subscriberCount == 2 }
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount >= 1 }
        let expected: [LocationUpdateEvent] = [
            .fix(try ConnectionSessionLocationTestValues.fix(index: 1)),
            .unavailable(.temporarilyUnavailable),
            .fix(try ConnectionSessionLocationTestValues.fix(index: 2))
        ]
        expected.forEach { source.yield($0) }
        await LocationRecordingBoundedWaiter.waitUntil("1人目へ届く") { first.events == expected }
        await LocationRecordingBoundedWaiter.waitUntil("2人目へ届く") { second.events == expected }
        XCTAssertEqual(source.makeUpdatesCallCount, 1)
    }

    /// 片方の購読を取消しても、もう片方へは届き続け、取得元の流れは終わりません。
    ///
    /// 責務: 1人が抜けた後の事象が残った購読者だけに届き、取得元の終了回数が 0 のままであることを確認します。
    func testCancellingOneSubscriberKeepsOtherReceiving() async throws {
        let distributor = makeDistributor()
        let leaving = startReading(distributor)
        let staying = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("2人が購読する") { distributor.subscriberCount == 2 }
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount == 1 }
        let first = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 1))
        source.yield(first)
        await LocationRecordingBoundedWaiter.waitUntil("両方へ届く") { leaving.events == [first] && staying.events == [first] }

        leaving.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("購読者が1人になる") { distributor.subscriberCount == 1 }
        let second = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 2))
        source.yield(second)
        await LocationRecordingBoundedWaiter.waitUntil("残った購読者へ届く") { staying.events == [first, second] }
        XCTAssertEqual(leaving.events, [first])
        XCTAssertEqual(source.terminationCount, 0)
        XCTAssertEqual(source.makeUpdatesCallCount, 1)
    }

    /// 最後の購読者がいなくなると取得元の流れを終え、購読者数が 0 になります。
    ///
    /// 責務: 1→0 で取得元の流れが1回終了し、`subscriberCount` が 0 になることを確認します。
    func testLastSubscriberLeavingStopsSource() async throws {
        let distributor = makeDistributor()
        let first = startReading(distributor)
        let second = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("2人が購読する") { distributor.subscriberCount == 2 }
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount == 1 }
        let event = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 1))
        source.yield(event)
        await LocationRecordingBoundedWaiter.waitUntil("両方へ届く") { first.events == [event] && second.events == [event] }

        first.cancel()
        second.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("購読者が0人になる") { distributor.subscriberCount == 0 }
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが終わる") { source.terminationCount == 1 }
    }

    /// 取得元の流れが自分から終わると、全購読者の流れが終わります。
    ///
    /// 責務: 取得元の自然終了で両方の読み手の `for await` が抜けることを確認します。
    func testSourceFinishingEndsAllSubscribers() async throws {
        let distributor = makeDistributor()
        let first = startReading(distributor)
        let second = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("2人が購読する") { distributor.subscriberCount == 2 }
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount == 1 }
        let event = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 1))
        source.yield(event)
        await LocationRecordingBoundedWaiter.waitUntil("両方へ届く") { first.events == [event] && second.events == [event] }

        source.finish()
        await LocationRecordingBoundedWaiter.waitUntil("1人目の流れが終わる") { first.didFinish }
        await LocationRecordingBoundedWaiter.waitUntil("2人目の流れが終わる") { second.didFinish }
    }

    /// 全員がいなくなった後に新しい購読者が来ると、取得元の流れを作り直して事象を届けます。
    ///
    /// 責務: 1→0→1 で `makeUpdates()` が2回目に呼ばれ、新しい流れの事象が新しい購読者へ届くことを確認します。
    func testResubscribingAfterAllLeftRestartsSource() async throws {
        let distributor = makeDistributor()
        let first = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作られる") { source.makeUpdatesCallCount == 1 }
        let old = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 1))
        source.yield(old)
        await LocationRecordingBoundedWaiter.waitUntil("最初の購読者へ届く") { first.events == [old] }
        first.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが終わる") { source.terminationCount == 1 }

        let next = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("取得元の流れが作り直される") { source.makeUpdatesCallCount == 2 }
        let fresh = LocationUpdateEvent.fix(try ConnectionSessionLocationTestValues.fix(index: 2))
        source.yield(fresh)
        await LocationRecordingBoundedWaiter.waitUntil("新しい購読者へ届く") { next.events == [fresh] }
    }

    /// 購読者数は購読と取消に合わせて増減します。
    ///
    /// 責務: 0・1・2・1・0 の各段階で `subscriberCount` が購読者数を返すことを確認します。
    func testSubscriberCountTracksSubscriptions() async {
        let distributor = makeDistributor()
        XCTAssertEqual(distributor.subscriberCount, 0)
        let first = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("1人") { distributor.subscriberCount == 1 }
        let second = startReading(distributor)
        await LocationRecordingBoundedWaiter.waitUntil("2人") { distributor.subscriberCount == 2 }
        first.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("1人に戻る") { distributor.subscriberCount == 1 }
        second.cancel()
        await LocationRecordingBoundedWaiter.waitUntil("0人に戻る") { distributor.subscriberCount == 0 }
    }
}

/// 購読した流れを別タスクで読み、受け取った事象と終了を記録する読み手です。
@MainActor
private final class LocationUpdateDistributorEventCollector {
    /// 受け取った事象です(受信順)。
    private(set) var events: [LocationUpdateEvent] = []
    /// 流れが終わって読み終えた場合は `true` です。
    private(set) var didFinish = false
    /// 流れを読むタスクです。
    private var task: Task<Void, Never>?

    /// 流れを渡して読み始めます。
    ///
    /// 責務: 流れを読み、受け取った事象と終了を記録するタスクを開始します。
    /// - Parameter stream: 読む流れ。
    init(stream: AsyncStream<LocationUpdateEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
            self?.didFinish = true
        }
    }

    /// 読むのをやめて購読を取消します。
    ///
    /// 責務: 読むタスクを取消し、流れの終了を配布役へ伝えます。
    func cancel() {
        task?.cancel()
    }
}
