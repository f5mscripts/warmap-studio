import SwiftUI

/// App-wide state: onboarding, settings, and first-launch seeding.
///
/// Settings are `@Published` properties that write through to `UserDefaults` on
/// change, rather than `@AppStorage`. `@AppStorage` is a `DynamicProperty` built for
/// views: inside an `ObservableObject` it stores and reads correctly but never fires
/// `objectWillChange`, so finishing onboarding would set the flag and leave the user
/// staring at the same screen.
@MainActor
public final class AppState: ObservableObject {

    private enum Key {
        static let onboarding = "hasCompletedOnboarding"
        static let seeded = "hasSeededDemo"
        static let exportPreset = "defaultExportPresetID"
        static let fps = "defaultFPS"
        static let dateFormat = "defaultDateFormat"
        static let mapStyle = "defaultMapStyle"
        static let autosave = "autosaveEnabled"
        static let previewQuality = "previewQuality"
    }

    private let defaults: UserDefaults

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }
    @Published public var defaultExportPresetID: String {
        didSet { defaults.set(defaultExportPresetID, forKey: Key.exportPreset) }
    }
    @Published public var defaultFPS: Int {
        didSet { defaults.set(defaultFPS, forKey: Key.fps) }
    }
    @Published public var defaultDateFormat: String {
        didSet { defaults.set(defaultDateFormat, forKey: Key.dateFormat) }
    }
    @Published public var defaultMapStyle: String {
        didSet { defaults.set(defaultMapStyle, forKey: Key.mapStyle) }
    }
    @Published public var autosaveEnabled: Bool {
        didSet { defaults.set(autosaveEnabled, forKey: Key.autosave) }
    }
    /// 0 draft, 1 normal, 2 high.
    @Published public var previewQuality: Int {
        didSet { defaults.set(previewQuality, forKey: Key.previewQuality) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        defaultExportPresetID = defaults.string(forKey: Key.exportPreset) ?? "tiktok"
        defaultFPS = defaults.object(forKey: Key.fps) as? Int ?? 30
        defaultDateFormat = defaults.string(forKey: Key.dateFormat)
            ?? HistoricalDate.Format.dayMonthNameYear.rawValue
        defaultMapStyle = defaults.string(forKey: Key.mapStyle) ?? MapStyle.military.rawValue
        autosaveEnabled = defaults.object(forKey: Key.autosave) as? Bool ?? true
        previewQuality = defaults.object(forKey: Key.previewQuality) as? Int ?? 1
    }

    /// Puts the WW2 demo in place the first time the app runs, so the dashboard is
    /// never empty and Play does something immediately.
    public func seedDemoIfNeeded() {
        guard !defaults.bool(forKey: Key.seeded) else { return }
        defaults.set(true, forKey: Key.seeded)
        guard ProjectStore.shared.listProjects().isEmpty else { return }
        try? ProjectStore.shared.save(ScenarioLibrary.ww2Europe())
    }
}

/// Four pages explaining what the app does, then out to the dashboard.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "map.fill",
             title: "Create historical maps",
             body: "Start from a real historical period, or invent your own. Every country, border and city is editable."),
        Page(symbol: "shield.lefthalf.filled",
             title: "Simulate wars",
             body: "Set army strength, economy, supply and morale, then let the simulator resolve the fighting — or script every event yourself."),
        Page(symbol: "arrow.left.and.right",
             title: "Animate borders",
             body: "Watch territory change hands with smooth advancing fronts, moving frontlines and camera moves."),
        Page(symbol: "square.and.arrow.up.fill",
             title: "Export videos",
             body: "Render straight to 9:16 for TikTok and Shorts, or 16:9 and square. What you see is exactly what gets written."),
    ]

    var body: some View {
        ZStack {
            Theme.atlasBackground.ignoresSafeArea()
            VStack(spacing: Theme.Metric.gutterLoose) {
                Spacer()

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: Theme.Metric.gutter) {
                            Image(systemName: pages[index].symbol)
                                .font(.system(size: 62, weight: .thin))
                                .foregroundStyle(Theme.goldLeaf)
                            Text(pages[index].title)
                                .font(Theme.Font.display(28))
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(pages[index].body)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 360)
                        }
                        .padding(Theme.Metric.gutterLoose)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Spacer()

                Button(page == pages.count - 1 ? "Create Your First War Map" : "Continue") {
                    if page == pages.count - 1 {
                        appState.hasCompletedOnboarding = true
                    } else {
                        withAnimation(Theme.Motion.standard) { page += 1 }
                    }
                }
                .buttonStyle(GoldButtonStyle())

                Button("Skip") { appState.hasCompletedOnboarding = true }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.bottom, Theme.Metric.gutterLoose)
            }
        }
    }
}

/// App preferences and storage management.
struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var storageUsed: String = "—"

    var body: some View {
        NavigationStack {
            Form {
                Section("Export defaults") {
                    Picker("Resolution", selection: $appState.defaultExportPresetID) {
                        ForEach(ExportPreset.builtIn) { preset in
                            Text("\(preset.name) · \(preset.resolutionLabel)").tag(preset.id)
                        }
                    }
                    Picker("Frame rate", selection: $appState.defaultFPS) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                }

                Section("Appearance") {
                    Picker("Default map style", selection: $appState.defaultMapStyle) {
                        ForEach(MapStyle.allCases) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    Picker("Date format", selection: $appState.defaultDateFormat) {
                        ForEach(HistoricalDate.Format.allCases) { format in
                            Text(format.displayName).tag(format.rawValue)
                        }
                    }
                    Picker("Preview quality", selection: $appState.previewQuality) {
                        Text("Draft").tag(0)
                        Text("Normal").tag(1)
                        Text("High").tag(2)
                    }
                    Text("Theme is dark throughout — the map is the only thing meant to be bright.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Projects") {
                    Toggle("Autosave", isOn: $appState.autosaveEnabled)
                    LabeledContent("Projects", value: "\(ProjectStore.shared.listProjects().count)")
                    LabeledContent("Storage used", value: storageUsed)
                    Text("Projects live only on this device, in the app's Documents folder. Nothing is uploaded.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Historical data") {
                    LabeledContent("Map geometry", value: "Natural Earth 110m")
                    LabeledContent("Territory units",
                                   value: "\((try? MapLibrary.shared.units().count) ?? 0)")
                    LabeledContent("Cities",
                                   value: "\((try? MapLibrary.shared.cities().count) ?? 0)")
                    LabeledContent("Countries", value: "\(CountryLibrary.all.count)")
                    Text("Natural Earth is public domain. Flags are drawn procedurally rather than bundled as artwork. See DATA_LICENSES.md in the repository.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("No analytics, no advertising, no tracking, no account. The app works entirely offline; the only network access is one you opt into by adding an AI key.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button("Show onboarding again") {
                        appState.hasCompletedOnboarding = false
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: measureStorage)
        }
    }

    private func measureStorage() {
        let directory = ProjectStore.shared.projectsDirectory
        let bytes = (try? FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .reduce(Int64(0)) { total, path in
                let full = directory.appendingPathComponent(path).path
                let attributes = try? FileManager.default.attributesOfItem(atPath: full)
                return total + Int64((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            }) ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        storageUsed = formatter.string(fromByteCount: bytes)
    }
}
