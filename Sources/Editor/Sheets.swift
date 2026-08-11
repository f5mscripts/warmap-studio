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

/// Configure strengths and let the simulator resolve the war.
struct SimulatorSheet: View {
    @ObservedObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss

    @State private var attacker: String = ""
    @State private var defender: String = ""
    @State private var attackerStrength = CountryStrength.major
    @State private var defenderStrength = CountryStrength.minor
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
                : "Resolves the war from the strengths below. Alternate outcomes are expected."
        }
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

                Section("Sides") {
                    Picker("Attacker", selection: $attacker) {
                        ForEach(store.project.countries) { Text($0.name).tag($0.id) }
                    }
                    Picker("Defender", selection: $defender) {
                        ForEach(store.project.countries) { Text($0.name).tag($0.id) }
                    }
                }

                if mode == .sandbox {
                    strengthSection("Attacker", $attackerStrength)
                    strengthSection("Defender", $defenderStrength)

                    Section("Resolution") {
                        VStack(alignment: .leading) {
                            Text("Luck \(Int(randomness * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: $randomness, in: 0...1).tint(Theme.Palette.gold)
                            Text("At 0% the outcome follows only from the strengths above.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Stepper("Seed \(seed)", value: $seed, in: 1...999_999)
                    }
                }

                if let result {
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
            }
            .navigationTitle("Auto Simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRunning ? "Running…" : "Simulate") { run() }
                        .disabled(isRunning || attacker.isEmpty || defender.isEmpty
                                  || attacker == defender || mode == .historical)
                }
            }
        }
        .onAppear {
            attacker = store.project.countries.first?.id ?? ""
            defender = store.project.countries.dropFirst().first?.id ?? ""
        }
    }

    private func strengthSection(_ title: String,
                                 _ binding: Binding<CountryStrength>) -> some View {
        Section(title) {
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
        let project = store.project
        let timeline = project.activeTimeline
        let attackerID = attacker
        let defenderID = defender
        let attackerValues = attackerStrength
        let defenderValues = defenderStrength
        let config = SimulationConfig(seed: UInt64(seed), randomness: randomness)

        Task.detached(priority: .userInitiated) {
            let war = project.wars.first ?? War(
                name: "War",
                interval: timeline.historicalRange,
                factions: [
                    Faction(name: "Attacker", colorHex: "5E6860",
                            memberCountryIDs: [attackerID]),
                    Faction(name: "Defender", colorHex: "B04A44",
                            memberCountryIDs: [defenderID]),
                ]
            )
            let simulator = (try? WarSimulator(config: config, library: .shared))
                ?? WarSimulator(config: config, neighbours: [:])
            let outcome = simulator.simulate(
                war: war,
                initialOwnership: timeline.initialOwnership,
                strengths: [attackerID: attackerValues, defenderID: defenderValues],
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
