import SwiftUI

/// Top-level router. Onboarding is shown once, then the dashboard becomes the home
/// surface for the rest of the app's life.
struct RootView: View {
    var body: some View {
        ZStack {
            Theme.atlasBackground.ignoresSafeArea()
            VStack(spacing: Theme.Metric.gutterTight) {
                Text("WarMap Studio")
                    .font(Theme.Font.screenTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Historical War Map Creator")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
