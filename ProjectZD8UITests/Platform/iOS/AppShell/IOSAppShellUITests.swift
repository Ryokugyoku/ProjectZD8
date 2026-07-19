#if os(iOS)
import XCTest

/// Verifies the launch behavior owned by the iOS AppShell.
final class IOSAppShellUITests: XCTestCase {
    /// Verifies that launching the iOS application presents the iOS-owned root layout.
    ///
    /// Responsibility: Confirms that the iOS AppShell is reachable from the process entry point.
    @MainActor
    func testLaunchShowsIOSAppShell() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["ios-app-shell"].waitForExistence(timeout: 5))
    }
}
#endif
