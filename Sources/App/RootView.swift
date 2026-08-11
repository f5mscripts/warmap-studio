import SwiftUI

/// Top-level router. Onboarding runs once; after that the dashboard is home.
struct RootView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                DashboardScreen()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(appState)
        .animation(Theme.Motion.standard, value: appState.hasCompletedOnboarding)
        .task {
            // Seed the demo before the dashboard first appears, so Play works
            // immediately on a fresh install.
            appState.seedDemoIfNeeded()
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
