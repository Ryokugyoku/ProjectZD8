#if os(iOS)
import SwiftUI

/// Renders the root layout owned exclusively by the iOS application.
struct IOSAppShellView: View {
    /// Provides the initial iOS screen without owning application or infrastructure state.
    ///
    /// Responsibility: Renders the iOS AppShell's current presentation-only content.
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ProjectZD8",
                systemImage: "car.side",
                description: Text("No feature is available yet.")
            )
            .accessibilityIdentifier("ios-app-shell")
            .navigationTitle("ProjectZD8")
        }
    }
}

#Preview {
    IOSAppShellView()
}
#endif
