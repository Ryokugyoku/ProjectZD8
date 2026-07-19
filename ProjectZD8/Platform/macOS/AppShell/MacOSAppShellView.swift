#if os(macOS)
import SwiftUI

/// Renders the root layout owned exclusively by the macOS application.
struct MacOSAppShellView: View {
    /// Provides the initial macOS screen without owning application or infrastructure state.
    ///
    /// Responsibility: Renders the macOS AppShell's current presentation-only content.
    var body: some View {
        ContentUnavailableView(
            "ProjectZD8",
            systemImage: "car.side",
            description: Text("No feature is available yet.")
        )
        .accessibilityIdentifier("macos-app-shell")
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    MacOSAppShellView()
}
#endif
