#if os(macOS)
import XCTest

/// Verifies the launch behavior owned by the macOS AppShell.
final class MacOSAppShellUITests: XCTestCase {
    /// Verifies that launching the macOS application presents the macOS-owned root layout.
    ///
    /// Responsibility: Confirms that the macOS AppShell is reachable from the process entry point.
    @MainActor
    func testLaunchShowsMacOSAppShell() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["macos-app-shell"].waitForExistence(timeout: 5))
    }
}
#endif
