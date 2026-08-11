import SwiftUI
import UniformTypeIdentifiers

/// The home surface: existing projects, and the ways to start a new one.
struct DashboardScreen: View {

    @EnvironmentObject private var appState: AppState
    @State private var summaries: [ProjectSummary] = []
    @State private var openProject: WarMapProject?
    @State private var showsWizard = false
    @State private var showsSettings = false
    @State private var showsImporter = false
    @State private var deleteTarget: ProjectSummary?
    @State private var error: WarMapError?

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 380),
                                    spacing: Theme.Metric.gutter)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.atlasBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Metric.gutterLoose) {
                        header

                        if summaries.isEmpty {
                            EmptyStateView(
                                systemImage: "map",
                                title: "No projects yet",
                                message: "Start from a historical preset, or build a map from scratch.",
                                actionTitle: "New Project",
                                action: { showsWizard = true }
                            )
                        } else {
                            VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
                                SectionHeader("PROJECTS") {
                                    Text("\(summaries.count)")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                }
                                LazyVGrid(columns: columns, spacing: Theme.Metric.gutter) {
                                    ForEach(summaries) { summary in
                                        ProjectCard(
                                            summary: summary,
                                            onOpen: { open(summary) },
                                            onDuplicate: { duplicate(summary) },
                                            onDelete: { deleteTarget = summary }
                                        )
                                    }
                                }
                            }
                        }

                        presetsSection
                    }
                    .padding(Theme.Metric.gutter)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Project", systemImage: "plus") { showsWizard = true }
                        Button("Import .warmap", systemImage: "square.and.arrow.down") {
                            showsImporter = true
                        }
                        Divider()
                        Button("Settings", systemImage: "gearshape") { showsSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(item: $openProject) { project in
                EditorScreen(project: project)
            }
            .sheet(isPresented: $showsWizard) {
                NewProjectWizard { project in
                    save(project)
                    openProject = project
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
            }
            .fileImporter(isPresented: $showsImporter,
                          allowedContentTypes: [.folder, .item],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("Delete project?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } })) {
                Button("Delete", role: .destructive) {
                    if let deleteTarget { performDelete(deleteTarget) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("“\(deleteTarget?.name ?? "")” will be removed from this device. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text([error?.errorDescription, error?.recoverySuggestion]
                    .compactMap { $0 }.joined(separator: "\n\n"))
            }
            .onAppear(perform: reload)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WarMap Studio")
                .font(Theme.Font.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Historical War Map Creator")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button {
                showsWizard = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(GoldButtonStyle())
            .padding(.top, Theme.Metric.gutterTight)
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
            SectionHeader("START FROM A SCENARIO")
            LazyVGrid(columns: columns, spacing: Theme.Metric.gutterTight) {
                ForEach(ScenarioLibrary.all) { preset in
                    Button {
                        let project = preset.build()
                        save(project)
                        openProject = project
                    } label: {
                        Panel(padding: Theme.Metric.gutterTight) {
                            HStack(spacing: Theme.Metric.gutterTight) {
                                Image(systemName: "flag.2.crossed.fill")
                                    .foregroundStyle(Theme.Palette.goldDim)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(Theme.Font.cardTitle)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Text("\(preset.periodLabel) · \(preset.subtitle)")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        summaries = ProjectStore.shared.listProjects()
    }

    private func open(_ summary: ProjectSummary) {
        do {
            openProject = try ProjectStore.shared.load(from: summary.url)
        } catch let failure as WarMapError {
            error = failure
        } catch {
            self.error = .projectCorrupt(name: summary.name, detail: error.localizedDescription)
        }
    }

    private func save(_ project: WarMapProject) {
        do {
            try ProjectStore.shared.save(project)
            reload()
        } catch let failure as WarMapError {
            error = failure
        } catch {
            self.error = .projectSaveFailed(detail: error.localizedDescription)
        }
    }

    private func duplicate(_ summary: ProjectSummary) {
        do {
            _ = try ProjectStore.shared.duplicate(summary)
            reload()
        } catch let failure as WarMapError {
            error = failure
        } catch {
            self.error = .projectSaveFailed(detail: error.localizedDescription)
        }
    }

    private func performDelete(_ summary: ProjectSummary) {
        do {
            try ProjectStore.shared.delete(summary)
            reload()
        } catch let failure as WarMapError {
            error = failure
        } catch {
            self.error = .projectSaveFailed(detail: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                _ = try ProjectStore.shared.importProject(from: url)
                reload()
            } catch let failure as WarMapError {
                error = failure
            } catch {
                self.error = .projectCorrupt(name: url.lastPathComponent,
                                             detail: error.localizedDescription)
            }
        case .failure(let failure):
            error = .projectCorrupt(name: "the selected file",
                                    detail: failure.localizedDescription)
        }
    }
}

/// One project on the dashboard.
struct ProjectCard: View {
    let summary: ProjectSummary
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Panel(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.name)
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(summary.periodLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.gold)
                        if !summary.subtitle.isEmpty {
                            Text(summary.subtitle)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(summary.modifiedAt, format: .relative(presentation: .named))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                            Spacer()
                            IconButton(systemName: "play.fill", label: "Play", action: onOpen)
                            IconButton(systemName: "square.on.square", label: "Duplicate",
                                       action: onDuplicate)
                            IconButton(systemName: "trash", label: "Delete",
                                       tint: Theme.Palette.danger, action: onDelete)
                        }
                        .padding(.top, 2)
                    }
                    .padding(Theme.Metric.gutterTight)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "pencil", action: onOpen)
            Button("Duplicate", systemImage: "square.on.square", action: onDuplicate)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            if let url = summary.thumbnailURL,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // No render yet: a tinted era placeholder rather than a blank box.
                LinearGradient(colors: [Theme.Palette.ocean, Theme.Palette.oceanDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(Theme.Palette.goldDim.opacity(0.5))
            }
        }
        .frame(height: 118)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            Text(summary.era.displayName.uppercased())
                .font(Theme.Font.ui(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Palette.textOnLight)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.Palette.gold))
                .padding(7)
        }
    }
}
