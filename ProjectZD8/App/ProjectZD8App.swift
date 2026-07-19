import SwiftUI

/// Defines the ProjectZD8 process entry point and selects the platform-owned root scene.
@main
struct ProjectZD8App: App {
    /// Provides the application window using the layout owned by the current platform.
    ///
    /// Responsibility: Wires the current Apple platform to its independent AppShell view.
    var body: some Scene {
        WindowGroup {
#if os(iOS)
            IOSAppShellView()
#elseif os(macOS)
            MacOSAppShellView()
#endif
        }
    }
}
