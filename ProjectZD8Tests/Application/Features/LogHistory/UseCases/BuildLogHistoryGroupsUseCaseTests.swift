import XCTest
@testable import ProjectZD8

final class BuildLogHistoryGroupsUseCaseTests: XCTestCase {
    private let t0 = RecordsFixtures.referenceDate
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func row(_ vehicle: VehicleID, start: TimeInterval, duration: TimeInterval = 100, reason: SessionEndReason = .userStopped, demo: Bool = false, odometerEnd: Double? = nil) -> LogHistorySessionRow {
        LogHistorySessionRow(session: RecordsFixtures.session(
            vehicleID: vehicle, startedAt: t0.addingTimeInterval(start), duration: duration, endReason: reason, isDemo: demo,
            odometerStart: odometerEnd.map { _ in 0 }, odometerEnd: odometerEnd
        ))
    }

    func testGroupsByVehicleLatestFirstWithTotals() {
        let a = VehicleID()
        let b = VehicleID()
        let rows = [
            row(a, start: 0, duration: 100, odometerEnd: 10),
            row(a, start: 1000, duration: 200, reason: .connectionLost, odometerEnd: 5),
            row(b, start: 5000, duration: 50)
        ]
        let groups = BuildLogHistoryGroupsUseCase().execute(rows: rows, vehicleNames: [a: "A", b: "B"], filter: LogHistoryFilter(), sortOrder: .newest, calendar: calendar)
        XCTAssertEqual(groups.map(\.id), [b, a])
        XCTAssertEqual(groups[1].vehicleName, "A")
        XCTAssertEqual(groups[1].sessionCount, 2)
        XCTAssertEqual(groups[1].interruptedCount, 1)
        XCTAssertEqual(groups[1].totalDuration, 300)
        XCTAssertEqual(groups[1].totalDistanceKilometers, 15)
        XCTAssertNil(groups[0].totalDistanceKilometers, "no distance available")
        XCTAssertEqual(groups[1].sessions.map(\.startedAt), [t0.addingTimeInterval(1000), t0])
    }

    func testPartialDistanceYieldsNoTotal() {
        let a = VehicleID()
        let rows = [row(a, start: 0, odometerEnd: 10), row(a, start: 10)]
        let groups = BuildLogHistoryGroupsUseCase().execute(rows: rows, vehicleNames: [:], filter: LogHistoryFilter(), sortOrder: .newest, calendar: calendar)
        XCTAssertNil(groups[0].totalDistanceKilometers)
        XCTAssertNil(groups[0].vehicleName)
    }

    func testSortOrders() {
        let a = VehicleID()
        let rows = [row(a, start: 0, duration: 300), row(a, start: 100, duration: 100), row(a, start: 200, duration: 200)]
        func order(_ sort: LogHistorySortOrder) -> [TimeInterval] {
            BuildLogHistoryGroupsUseCase().execute(rows: rows, vehicleNames: [:], filter: LogHistoryFilter(), sortOrder: sort, calendar: calendar)[0].sessions.compactMap(\.duration)
        }
        XCTAssertEqual(order(.newest), [200, 100, 300])
        XCTAssertEqual(order(.oldest), [300, 100, 200])
        XCTAssertEqual(order(.longestDuration), [300, 200, 100])
        XCTAssertEqual(order(.shortestDuration), [100, 200, 300])
    }

    func testFiltersAreCombined() {
        let a = VehicleID()
        let rows = [
            row(a, start: 0, reason: .userStopped),
            row(a, start: 100, reason: .connectionLost, demo: true),
            row(a, start: 200, reason: .connectionLost)
        ]
        func count(_ filter: LogHistoryFilter) -> Int {
            BuildLogHistoryGroupsUseCase().execute(rows: rows, vehicleNames: [:], filter: filter, sortOrder: .newest, calendar: calendar).first?.sessionCount ?? 0
        }
        XCTAssertEqual(count(LogHistoryFilter(endReason: .connectionLost)), 2)
        XCTAssertEqual(count(LogHistoryFilter(dataKind: .demo)), 1)
        XCTAssertEqual(count(LogHistoryFilter(dataKind: .real)), 2)
        XCTAssertEqual(count(LogHistoryFilter(endReason: .connectionLost, dataKind: .real)), 1)
        XCTAssertEqual(count(LogHistoryFilter(endReason: .appTerminated)), 0)
    }

    func testDateRangeBoundariesAreInclusiveOfWholeDays() {
        let a = VehicleID()
        let dayStart = calendar.startOfDay(for: t0)
        let inDay = LogHistorySessionRow(session: RecordsFixtures.session(vehicleID: a, startedAt: dayStart.addingTimeInterval(86_399)))
        let nextDay = LogHistorySessionRow(session: RecordsFixtures.session(vehicleID: a, startedAt: dayStart.addingTimeInterval(86_400)))
        let prevDay = LogHistorySessionRow(session: RecordsFixtures.session(vehicleID: a, startedAt: dayStart.addingTimeInterval(-1)))
        let filter = LogHistoryFilter(startDate: t0, endDate: t0)
        XCTAssertTrue(filter.matches(inDay, calendar: calendar))
        XCTAssertFalse(filter.matches(nextDay, calendar: calendar))
        XCTAssertFalse(filter.matches(prevDay, calendar: calendar))
        XCTAssertTrue(filter.isActive)
        XCTAssertFalse(LogHistoryFilter().isActive)
    }
}
