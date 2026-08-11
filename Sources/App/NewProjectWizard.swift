import SwiftUI

/// Three steps: where in the world, when in history, and what shape the video is.
struct NewProjectWizard: View {

    let onCreate: (WarMapProject) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var name = "Untitled Map"
    @State private var regionID = "europe"
    @State private var era: HistoricalEra = .worldWarTwo
    @State private var startYear = 1939
    @State private var endYear = 1945
    @State private var presetID: String?
    @State private var exportPresetID = "tiktok"
    @State private var regions: [MapRegion] = []
    @State private var mapStyle: MapStyle = .military

    /// Historical map presets, layered on top of the geographic regions.
    private let historicalMaps: [(id: String, name: String, region: String, era: HistoricalEra)] = [
        ("roman", "Roman Empire", "mediterranean", .classical),
        ("medieval", "Medieval Europe", "europe", .medieval),
        ("ottoman", "Ottoman Empire", "middle_east", .earlyModern),
        ("napoleonic", "Napoleonic Europe", "europe", .napoleonic),
        ("ww1", "WW1 Europe", "europe", .worldWarOne),
        ("ww2", "WW2 Europe", "europe", .worldWarTwo),
        ("coldwar", "Cold War Europe", "europe", .coldWar),
        ("ancient-med", "Ancient Mediterranean", "mediterranean", .ancient),
        ("near-east", "Ancient Near East", "middle_east", .ancient),
    ]

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case 0: mapStep
                case 1: periodStep
                default: formatStep
                }
            }
            .navigationTitle(["Choose a map", "Choose a period", "Choose a format"][min(step, 2)])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Cancel" : "Back") {
                        if step == 0 { dismiss() } else { step -= 1 }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(step == 2 ? "Create" : "Next") {
                        if step == 2 { create() } else { step += 1 }
                    }
                }
            }
            .onAppear { regions = (try? MapLibrary.shared.regions()) ?? [] }
        }
    }

    // MARK: - Steps

    private var mapStep: some View {
        Group {
            Section("Region") {
                Picker("Map", selection: $regionID) {
                    ForEach(regions) { region in
                        Text(region.name).tag(region.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Historical map presets") {
                ForEach(historicalMaps, id: \.id) { preset in
                    Button {
                        regionID = preset.region
                        era = preset.era
                        startYear = preset.era.startYear
                        endYear = preset.era.endYear
                        mapStyle = preset.era.suggestedMapStyle
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            Text(preset.era.yearRangeLabel)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Historical maps are ownership overlays on the bundled geometry — accurate enough for the video style, not a surveyed historical atlas. You can import your own GeoJSON later.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var periodStep: some View {
        Group {
            Section("Era") {
                Picker("Era", selection: $era) {
                    ForEach(HistoricalEra.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: era) { _, newValue in
                    startYear = newValue.startYear
                    endYear = newValue.endYear
                    mapStyle = newValue.suggestedMapStyle
                }
                Text(era.summary).font(.caption).foregroundStyle(.secondary)
            }
            Section("Years") {
                Stepper("Start \(yearLabel(startYear))", value: $startYear,
                        in: -3000...2100)
                Stepper("End \(yearLabel(endYear))", value: $endYear,
                        in: -3000...2100)
                if endYear <= startYear {
                    Label("The end year must be after the start year.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
            Section("Start from a scenario") {
                Picker("Scenario", selection: $presetID) {
                    Text("Empty map").tag(String?.none)
                    ForEach(ScenarioLibrary.all) { preset in
                        Text(preset.name).tag(String?.some(preset.id))
                    }
                }
            }
        }
    }

    private var formatStep: some View {
        Group {
            Section("Name") {
                TextField("Project name", text: $name)
            }
            Section("Video format") {
                Picker("Format", selection: $exportPresetID) {
                    ForEach(ExportPreset.builtIn) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(preset.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Map style") {
                Picker("Style", selection: $mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func yearLabel(_ year: Int) -> String {
        year <= 0 ? "\(1 - year) BC" : "\(year)"
    }

    // MARK: - Creation

    private func create() {
        // Starting from a scenario means taking it wholesale, only renamed — the
        // preset already contains a working timeline.
        if let presetID, let preset = ScenarioLibrary.preset(presetID) {
            var project = preset.build()
            project.id = UUID()
            if name != "Untitled Map" { project.name = name }
            onCreate(project)
            dismiss()
            return
        }

        let safeEnd = max(endYear, startYear + 1)
        let range = HistoricalInterval(start: HistoricalDate(year: startYear),
                                       end: HistoricalDate(year: safeEnd))
        let region = regions.first { $0.id == regionID }
        let bounds = region?.bounds ?? .world

        // Everything starts neutral; the user paints ownership with the Territory tool.
        var timeline = Timeline(duration: 30,
                                historicalRange: range,
                                initialCamera: MapCamera.fitting(
                                    bounds,
                                    in: CGSize(width: 1080, height: 1920)))
        timeline.items = [
            TimelineItem(title: "Date counter", start: 0, duration: 30, easing: .linear,
                         action: .showText(.dateCounter(format: era.startYear < 1500
                                                        ? .yearOnly : .dayMonthNameYear)))
        ]

        let project = WarMapProject(
            name: name.isEmpty ? "Untitled Map" : name,
            subtitle: region?.name ?? "",
            era: era,
            mapRegionID: regionID,
            mapStyle: mapStyle,
            exportPreset: ExportPreset.builtIn.first { $0.id == exportPresetID } ?? .tiktok,
            timeline: timeline,
            countries: CountryLibrary.existing(on: HistoricalDate(year: startYear))
        )
        onCreate(project)
        dismiss()
    }
}
