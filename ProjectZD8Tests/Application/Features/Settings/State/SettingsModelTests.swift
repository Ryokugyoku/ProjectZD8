import XCTest
@testable import ProjectZD8

@MainActor
final class SettingsModelTests: XCTestCase {
    private func makeModel(_ store: RecordsFakeSettingsStore) -> SettingsModel {
        SettingsModel(store: store, appVersion: "1.2", appBuild: "34")
    }

    func testLoadsStoredSettingsAndAbout() {
        let store = RecordsFakeSettingsStore(settings: AppSettings(appearance: .dark, isDemoModeEnabled: true, localRawRetention: .days90))
        let model = makeModel(store)
        XCTAssertEqual(model.settings, store.current)
        XCTAssertEqual(model.state.versionText, "1.2 (34)")
        XCTAssertEqual(SettingsState.appearanceOptions.map(\.value), AppAppearance.allCases)
        XCTAssertEqual(SettingsState.retentionOptions.map(\.nameKey), ["settings.retention.days30", "settings.retention.days90", "settings.retention.unlimited"])
    }

    func testChangesAreSavedAndPublished() {
        let store = RecordsFakeSettingsStore()
        let model = makeModel(store)
        var published: [AppSettings] = []
        model.onChange = { published.append($0) }
        model.send(.appearanceChanged(.light))
        model.send(.demoModeChanged(true))
        model.send(.localRawRetentionChanged(.unlimited))
        XCTAssertEqual(store.current, AppSettings(appearance: .light, isDemoModeEnabled: true, localRawRetention: .unlimited))
        XCTAssertEqual(model.settings, store.current)
        XCTAssertEqual(published.count, 3)
        XCTAssertEqual(published.last, store.current)
        XCTAssertEqual(store.saveCount, 3)
    }

    func testUnchangedValueDoesNotSaveOrPublish() {
        let store = RecordsFakeSettingsStore()
        let model = makeModel(store)
        var count = 0
        model.onChange = { _ in count += 1 }
        model.send(.appearanceChanged(store.current.appearance))
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testReloadPicksUpExternalChangeWithoutWriting() {
        let store = RecordsFakeSettingsStore()
        let model = makeModel(store)
        var published: [AppSettings] = []
        model.onChange = { published.append($0) }
        store.overwrite(AppSettings(isDemoModeEnabled: true, localRawRetention: .days90))
        model.send(.reloadRequested)
        XCTAssertEqual(model.settings.isDemoModeEnabled, true)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(store.saveCount, 0)
    }
}
