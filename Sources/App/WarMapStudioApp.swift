import SwiftUI

@main
struct WarMapStudioApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.gold)
        }
    }
}
