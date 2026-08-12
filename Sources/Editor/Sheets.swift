import Photos
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export

/// Choose a format, render, then save or share.
struct ExportSheet: View {
    let project: WarMapProject

    @Environment(\.dismiss) private var dismiss
    @State private var preset: ExportPreset = .tiktok
    @State private var customWidth = 1080
    @State private var customHeight = 1920
    @State private var fps = 30
    @State private var useCustom = false
    @State private var progress: ExportProgress?
    @State private var outputURL: URL?
    @State private var error: WarMapError?
    @State private var exporter = VideoExporter()
    @State private var task: Task<Void, Never>?
    @State private var savedToPhotos = false

    private var resolved: ExportPreset {
        useCustom ? .custom(width: customWidth, height: customHeight, fps: fps)
                  : ExportPreset(id: preset.id, name: preset.name, detail: preset.detail,
                                 width: preset.width, height: preset.height, fps: fps,
                                 codec: preset.codec)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Preset", selection: $preset) {
                        ForEach(ExportPreset.builtIn) { option in
                            VStack(alignment: .leading) {
                                Text(option.name)
                                Text(option.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(option)
                        }
                    }
                    .disabled(useCustom)

                    Toggle("Custom resolution", isOn: $useCustom)
                    if useCustom {
                        Stepper("Width \(customWidth)", value: $customWidth,
                                in: 240...3840, step: 60)
                        Stepper("Height \(customHeight)", value: $customHeight,
                                in: 240...3840, step: 60)
                    }

                    Picker("Frame rate", selection: $fps) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                }

                Section("Output") {
                    LabeledContent("Resolution", value: resolved.resolutionLabel)
                    LabeledContent("Duration",
                                   value: String(format: "%.0f seconds", project.timeline.duration))
                    LabeledContent("Frames",
                                   value: "\(Int(project.timeline.duration * Double(resolved.fps)))")
                    LabeledContent("Estimated size", value: sizeText)
                }

                if let progress {
                    Section("Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress.fraction)
                                .tint(Theme.Palette.gold)
                            Text(progress.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let outputURL {
                    Section("Finished") {
                        ShareLink(item: outputURL) {
                            Label("Share video", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            saveToPhotos(outputURL)
                        } label: {
                            Label(savedToPhotos ? "Saved to Photos" : "Save to Photos",
                                  systemImage: savedToPhotos ? "checkmark.circle.fill" : "photo")
                        }
                        .disabled(savedToPhotos)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(progress == nil || outputURL != nil ? "Close" : "Cancel") {
                        task?.cancel()
                        Task { await exporter.cancel() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Render") { startExport() }
                        .disabled(progress != nil && outputURL == nil)
                }
            }
            .alert("Export failed",
                   isPresented: Binding(get: { error != nil },
                                        set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text([error?.errorDescription, error?.recoverySuggestion]
                    .compactMap { $0 }.joined(separator: "\n\n"))
            }
        }
        .onAppear {
            preset = project.exportPreset
            fps = project.exportPreset.fps
        }
    }

    private var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: resolved.estimatedBytes(duration: project.timeline.duration))
    }

    private func startExport() {
        outputURL = nil
        savedToPhotos = false
        progress = ExportProgress(stage: .preparing, fraction: 0)

        let package = ProjectStore.shared.existingPackage(for: project.id)
        let request = VideoExporter.Request(
            timeline: project.activeTimeline,
            countries: project.countryIndex,
            style: project.renderStyle,
            projection: project.projection,
            preset: resolved,
            audioClips: project.audioClips,
            audioDirectory: package.map { ProjectStore.shared.audioDirectory(in: $0) }
        )

        task = Task {
            do {
                let url = try await exporter.export(request) { update in
                    Task { @MainActor in progress = update }
                }
                await MainActor.run {
                    outputURL = url
                    progress = ExportProgress(stage: .finished, fraction: 1)
                }
            } catch let failure as WarMapError {
                await MainActor.run {
                    progress = nil
                    if !failure.isSilent { error = failure }
                }
            } catch {
                await MainActor.run {
                    progress = nil
                    self.error = .exportFailed(stage: "rendering",
                                               detail: error.localizedDescription)
                }
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in error = .photoLibraryDenied }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, failure in
                Task { @MainActor in
                    if success {
                        savedToPhotos = true
                    } else {
                        error = .exportFailed(stage: "saving to Photos",
                                              detail: failure?.localizedDescription ?? "unknown")
                    }
                }
            }
        }
    }
}

// MARK: - Auto simulator

/// Pick both coalitions, weigh them against each other, and let the simulator
/// resolve the war.
///
/// Every member of both sides is chosen by hand. Nothing is auto-filled from
/// alliances: who joins a war is the most interesting decision in the whole app, and
/// inferring it would quietly take that decision away.
struct SimulatorSheet: View {
    @ObservedObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss

    @State private var sideA: [String] = []
    @State private var sideB: [String] = []
    @State private var search = ""
    @State private var sideAStrength = CountryStrength.major
    @State private var sideBStrength = CountryStrength.minor
    @State private var randomness = 0.35
    @State private var seed = 20_260_811
    @State private var result: SimulationResult?
    @State private var isRunning = false
    @State private var mode: Mode = .sandbox

    enum Mode: String, CaseIterable, Identifiable {
        case historical, sandbox
        var id: String { rawValue }
        var title: String { self == .historical ? "Historical" : "Sandbox" }
        var explanation: String {
            self == .historical
                ? "Keeps the scripted events already on the timeline. Nothing is invented."
                : "Resolves the war from the coalitions and strengths below. Alternate outcomes are expected."
        }
    }

    /// Which side a country is on, if either.
    private enum Side { case a, b }

    private var date: HistoricalDate { store.project.activeTimeline.historicalRange.start }

    private var matched: [Country] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.project.countries }
        return store.project.countries.filter {
            $0.name.lowercased().contains(query) || $0.shortName.lowercased().contains(query)
        }
    }

    /// The pooled figure the engine will fight with: the mean member's offensive
    /// power scaled by `count^0.85`, so five allies are worth about 3.9 of one.
    private func pooledPower(_ members: [String], _ strength: CountryStrength) -> Double {
        guard !members.isEmpty else { return 0 }
        return strength.offensivePower * pow(Double(members.count), 0.85)
    }

    private var canSimulate: Bool {
        !sideA.isEmpty && !sideB.isEmpty && mode == .sandbox && !isRunning
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                matchupSection

                Section("Add countries") {
                    TextField("Search", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if matched.isEmpty {
                        Text("No country matches “\(search)”.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(matched) { country in
                        countryRow(country)
                    }
                }

                if mode == .sandbox {
                    strengthSection("Side A strength", $sideAStrength)
                    strengthSection("Side B strength", $sideBStrength)

                    Section("Resolution") {
                        VStack(alignment: .leading) {
                            Text("Luck \(Int(randomness * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: $randomness, in: 0...1).tint(Theme.Palette.gold)
                            Text("Luck is drawn once for the whole war as well as tick by tick, so a weaker coalition can genuinely win some seeds. At 0% the outcome follows only from the strengths.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Stepper("Seed \(seed)", value: $seed, in: 1...999_999)
                    }
                }

                if let result {
                    resultSection(result)
                }
            }
            .navigationTitle("Auto Simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRunning ? "Running…" : "Simulate") { run() }
                        .disabled(!canSimulate)
                }
            }
            .onAppear(perform: seedFromProject)
        }
    }

    /// Starts from the war the project already describes, if it has one.
    ///
    /// This is not the auto-filling of allies the design rules out: it is the user's
    /// own list, loaded so they can edit it rather than retype it. A project without
    /// a war opens with both sides empty.
    private func seedFromProject() {
        guard sideA.isEmpty, sideB.isEmpty, let war = store.project.wars.first else { return }
        sideA = war.factions.first?.memberCountryIDs ?? []
        sideB = war.factions.dropFirst().first?.memberCountryIDs ?? []
    }

    // MARK: - The matchup

    private var matchupSection: some View {
        Section("The matchup") {
            coalition(title: "Side A", members: sideA, strength: sideAStrength,
                      tint: Theme.Palette.gold, side: .a)
            coalition(title: "Side B", members: sideB, strength: sideBStrength,
                      tint: Theme.Palette.danger, side: .b)
            if sideA.isEmpty || sideB.isEmpty {
                Text("Pick at least one country for each side.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func coalition(title: String, members: [String], strength: CountryStrength,
                           tint: Color, side: Side) -> some View {
        let power = pooledPower(members, strength)
        let opposing = side == .a ? pooledPower(sideB, sideBStrength)
                                  : pooledPower(sideA, sideAStrength)
        let scale = max(power, opposing, 0.0001)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.Font.ui(13, weight: .semibold))
                Spacer()
                Text(members.isEmpty ? "—" : String(format: "%.1f", power))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            // The bar is the thing to watch while adding countries: it is the same
            // pooled figure the simulator will actually fight with.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.slate)
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * CGFloat(power / scale))
                }
            }
            .frame(height: 7)
            .animation(Theme.Motion.quick, value: power)

            if members.isEmpty {
                Text("No countries yet").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.self) { id in
                    if let country = store.project.countryIndex[id] {
                        Button {
                            remove(id)
                        } label: {
                            HStack(spacing: 8) {
                                CountryChip(country: country, date: date, isSelected: true)
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func countryRow(_ country: Country) -> some View {
        HStack(spacing: 10) {
            FlagView(country: country, date: date)
                .frame(width: 26, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Theme.Palette.rule, lineWidth: 0.5))
            Text(country.name).font(Theme.Font.ui(13, weight: .medium))
            Spacer()
            sideButton("A", side: .a, country: country, tint: Theme.Palette.gold)
            sideButton("B", side: .b, country: country, tint: Theme.Palette.danger)
        }
    }

    private func sideButton(_ label: String, side: Side, country: Country,
                            tint: Color) -> some View {
        let members = side == .a ? sideA : sideB
        let isMember = members.contains(country.id)
        return Button {
            if isMember { remove(country.id) } else { add(country.id, to: side) }
        } label: {
            Text(label)
                .font(Theme.Font.ui(12, weight: .bold))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: Theme.Metric.cornerSmall)
                    .fill(isMember ? tint : Theme.Palette.slate))
                .foregroundStyle(isMember ? Theme.Palette.textOnLight : Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(country.name) on side \(label)")
    }

    // MARK: - Membership

    /// A country belongs to at most one side, so joining one leaves the other.
    private func add(_ id: String, to side: Side) {
        sideA.removeAll { $0 == id }
        sideB.removeAll { $0 == id }
        switch side {
        case .a: sideA.append(id)
        case .b: sideB.append(id)
        }
    }

    private func remove(_ id: String) {
        sideA.removeAll { $0 == id }
        sideB.removeAll { $0 == id }
    }

    // MARK: - Result

    private func resultSection(_ result: SimulationResult) -> some View {
        Section("Result") {
            if result.capitulated.isEmpty {
                Text("No side was knocked out before the end date.")
                    .font(.caption)
            } else {
                ForEach(result.capitulated, id: \.self) { id in
                    Label("\(store.project.countryIndex[id]?.name ?? id) capitulated",
                          systemImage: "flag.slash.fill")
                    .font(.caption)
                }
            }
            Text("\(result.items.count) clips generated")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(result.log.prefix(12), id: \.self) { line in
                Text(line).font(.system(size: 11, design: .monospaced))
            }
            Button("Apply to timeline") { apply(result) }
                .buttonStyle(GoldButtonStyle())
        }
    }

    private func strengthSection(_ title: String,
                                 _ binding: Binding<CountryStrength>) -> some View {
        Section(title) {
            Text("Applied to every country on this side.")
                .font(.caption2).foregroundStyle(.secondary)
            factor("Military", binding.military)
            factor("Economy", binding.economy)
            factor("Population", binding.population)
            factor("Technology", binding.technology)
            factor("Supply", binding.supply)
            factor("Morale", binding.morale)
        }
    }

    private func factor(_ name: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0.1...2).tint(Theme.Palette.gold)
        }
    }

    private func run() {
        isRunning = true
        // Everything the background task needs is copied out first: capturing the
        // view's state directly would drag a non-Sendable SwiftUI struct across the
        // isolation boundary.
        let timeline = store.project.activeTimeline
        let membersA = sideA
        let membersB = sideB
        let valuesA = sideAStrength
        let valuesB = sideBStrength
        let config = SimulationConfig(seed: UInt64(seed), randomness: randomness)

        Task.detached(priority: .userInitiated) {
            // The picked coalitions replace whatever the project's own war says: this
            // sheet exists precisely to ask "what if these two sides fought?".
            let war = War(
                name: "Simulated War",
                interval: timeline.historicalRange,
                factions: [
                    Faction(name: "Side A", colorHex: "5E6860",
                            memberCountryIDs: membersA,
                            leaderCountryID: membersA.first),
                    Faction(name: "Side B", colorHex: "B04A44",
                            memberCountryIDs: membersB,
                            leaderCountryID: membersB.first),
                ]
            )
            var strengths: [String: CountryStrength] = [:]
            for id in membersA { strengths[id] = valuesA }
            for id in membersB { strengths[id] = valuesB }

            let simulator = (try? WarSimulator(config: config, library: .shared))
                ?? WarSimulator(config: config, neighbours: [:])
            let outcome = simulator.simulate(
                war: war,
                initialOwnership: timeline.initialOwnership,
                strengths: strengths,
                timeline: timeline
            )
            await MainActor.run {
                result = outcome
                isRunning = false
            }
        }
    }

    private func apply(_ result: SimulationResult) {
        store.apply("Apply Simulation") { project in
            project.activeTimeline.items.append(contentsOf: result.items)
        }
        dismiss()
    }
}

// MARK: - Alternate history

/// Fork the timeline without disturbing the original.
struct BranchSheet: View {
    @ObservedObject var store: EditorStore
    let currentDate: HistoricalDate
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Timelines") {
                    Button {
                        store.switchToBranch(nil)
                        dismiss()
                    } label: {
                        row(title: "Original Timeline",
                            detail: "Historical",
                            isActive: store.project.activeBranchID == nil)
                    }
                    ForEach(store.project.branches) { branch in
                        Button {
                            store.switchToBranch(branch.id)
                            dismiss()
                        } label: {
                            row(title: branch.name,
                                detail: "Diverges \(branch.divergenceDate.formatted(.monthNameYear))",
                                isActive: store.project.activeBranchID == branch.id)
                        }
                    }
                }

                Section("New branch") {
                    TextField("What if…", text: $name)
                    TextField("Note (optional)", text: $note)
                    LabeledContent("Diverges at",
                                   value: currentDate.formatted(.dayMonthNameYear))
                    Button("Create branch") {
                        store.createBranch(named: name.isEmpty ? "Alternate Timeline" : name,
                                           at: currentDate, note: note)
                        dismiss()
                    }
                    .buttonStyle(GoldButtonStyle())
                    Text("The original timeline is copied up to this date and left untouched.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("What If?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func row(title: String, detail: String, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.Palette.textPrimary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark").foregroundStyle(Theme.Palette.gold)
            }
        }
    }
}
