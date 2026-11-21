import XCTest
@testable import ProjectZD8

/// `VehicleSpeedSampleExtractor` が、Service 0x01・PID 0x0D の生ログだけを車速の観測へ直すことを検証します。
final class VehicleSpeedSampleExtractorTests: XCTestCase {
    private let extractor = VehicleSpeedSampleExtractor()
    private typealias Fixtures = RoadRegulationTimeSourceFixtures

    /// 責務: 0x01 / 0x0D / [0x3C] が 60 km/h になり、時刻の情報が引き継がれることを確かめます。
    func testSpeedEntryIsExtracted() {
        let entry = Fixtures.rawEntry(payload: [0x3C])
        let observation = extractor.observation(from: entry)
        XCTAssertEqual(observation?.kph, 60)
        XCTAssertEqual(observation?.observedAt, entry.observedAt)
        XCTAssertEqual(observation?.monotonicNanoseconds, 7_000_000_000)
    }

    /// 責務: 単調時刻の無い生ログが、単調時刻なしの観測になる(捨てない)ことを確かめます。
    func testMissingMonotonicTimeIsKeptAsNil() {
        let observation = extractor.observation(from: Fixtures.rawEntry(payload: [0x10], monotonic: nil))
        XCTAssertEqual(observation?.kph, 16)
        XCTAssertNil(observation?.monotonicNanoseconds)
    }

    /// 責務: 先頭バイトだけを車速に使い、後続のバイトは無視することを確かめます。
    func testOnlyFirstPayloadByteIsUsed() {
        XCTAssertEqual(extractor.observation(from: Fixtures.rawEntry(payload: [0x3C, 0xFF, 0x01]))?.kph, 60)
    }

    /// 責務: 0 km/h が欠損ではなく 0 の観測になることを確かめます。
    func testZeroSpeedIsAValidObservation() {
        XCTAssertEqual(extractor.observation(from: Fixtures.rawEntry(payload: [0x00]))?.kph, 0)
    }

    /// 責務: 範囲の上端(255)が、そのまま観測になることを確かめます。
    func testUpperBoundSpeedIsAccepted() {
        XCTAssertEqual(extractor.observation(from: Fixtures.rawEntry(payload: [0xFF]))?.kph, 255)
    }

    /// 責務: payload が空の時は nil になることを確かめます。
    func testEmptyPayloadReturnsNil() {
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(payload: [])))
    }

    /// 責務: PID 0x0D 以外(エンジン回転 0x0C など)は nil になることを確かめます。
    func testOtherPIDsAreIgnored() {
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(pid: 0x0C, payload: [0x3C])))
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(pid: 0x0E, payload: [0x3C])))
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(pid: 0x00, payload: [0x3C])))
    }

    /// 責務: Service 0x01 以外は、PID が 0x0D でも nil になることを確かめます。
    func testOtherServicesAreIgnored() {
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(service: 0x02, payload: [0x3C])))
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(service: 0x09, payload: [0x3C])))
        XCTAssertNil(extractor.observation(from: Fixtures.rawEntry(service: 0x00, payload: [0x3C])))
    }
}
