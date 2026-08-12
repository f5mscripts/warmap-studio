import SwiftUI

/// The tools on the left rail.
enum MapTool: String, CaseIterable, Identifiable {
    case select, pan, zoom, country, territory, army, frontline, battle,
         city, arrow, text, flag, camera, eraser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .pan: return "Pan"
        case .zoom: return "Zoom"
        case .country: return "Country"
        case .territory: return "Territory"
        case .army: return "Army"
        case .frontline: return "Frontline"
        case .battle: return "Battle"
        case .city: return "City"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .flag: return "Flag"
        case .camera: return "Camera"
        case .eraser: return "Eraser"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.draw"
        case .zoom: return "magnifyingglass"
        case .country: return "flag.square"
        case .territory: return "paintbrush.fill"
        case .army: return "shield.lefthalf.filled"
        case .frontline: return "scribble"
        case .battle: return "burst.fill"
        case .city: return "building.2"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .flag: return "flag"
        case .camera: return "camera.viewfinder"
        case .eraser: return "eraser"
        }
    }

    /// What the tool does on a tap, shown as a hint under the map.
    var hint: String {
        switch self {
        case .select: return "Tap a territory to inspect it"
        case .pan: return "Drag to move the map, pinch to zoom"
        case .zoom: return "Pinch to zoom"
        case .country: return "Tap a territory to see who holds it"
        case .territory: return "Tap a territory to give it to the selected country"
        case .army: return "Tap to place an army for the selected country"
        case .frontline: return "Tap along the front to place points, then Finish"
        case .battle: return "Tap where the battle happened"
        case .city: return "Tap to place a custom city"
        case .arrow: return "Tap a start and an end point"
        case .text: return "Tap to place a text element"
        case .flag: return "Tap a territory to place its flag"
        case .camera: return "Frame the map, then add a camera keyframe"
        case .eraser: return "Tap an element to remove it"
        }
    }
}

/// The main editing surface: toolbar, tool rail, map and timeline.
///
/// On a wide screen the rail and inspector sit alongside the map; on iPhone they
/// collapse into sheets so the map keeps as much room as possible.
struct EditorScreen: View {

    @StateObject private var store: EditorStore
    @StateObject private var playback = PlaybackController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var tool: MapTool = .select
    @State private var selectedItemID: UUID?
    @State private var selectedCountryID: String?
    @State private var selectedTerritoryID: String?
    @State private var interactiveCamera: MapCamera?
    @State private var showsInspector = false
    @State private var showsExport = false
    @State private var showsSimulator = false
    @State private var showsBranches = false
    @State private var frontlineDraft: [GeoCoordinate] = []
    @State private var errorMessage: String?

    init(project: WarMapProject) {
        _store = StateObject(wrappedValue: EditorStore(project: project))
    }

    private var timeline: Timeline { store.project.activeTimeline }

    private var snapshot: WorldSnapshot {
        TimelineEvaluator(timeline: timeline).snapshot(at: playback.time)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.Palette.rule)

            HStack(spacing: 0) {
                if sizeClass == .regular {
                    toolRail
                    Divider().overlay(Theme.Palette.rule)
                }

                mapArea

                if sizeClass == .regular, showsInspector {
                    Divider().overlay(Theme.Palette.rule)
                    InspectorPanel(store: store,
                                   snapshot: snapshot,
                                   playback: playback,
                                   selectedItemID: $selectedItemID,
                                   selectedCountryID: $selectedCountryID,
                                   selectedTerritoryID: $selectedTerritoryID)
                        .frame(width: Theme.Metric.inspectorWidth)
                }
            }

            Divider().overlay(Theme.Palette.rule)
            TimelineView(store: store, playback: playback, selectedItemID: $selectedItemID)
                .frame(height: sizeClass == .regular
                       ? Theme.Metric.timelineHeight
                       : Theme.Metric.timelineHeight * 0.75)
        }
        .background(Theme.Palette.charcoal)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            playback.duration = timeline.duration
        }
        .onChange(of: store.revision) {
            playback.duration = timeline.duration
        }
        .onChange(of: scenePhase) { _, phase in
            // Never leave a project only in memory.
            if phase != .active { store.flush() }
        }
        .sheet(isPresented: $showsExport) {
            ExportSheet(project: store.project)
        }
        .sheet(isPresented: $showsSimulator) {
            SimulatorSheet(store: store)
        }
        .sheet(isPresented: $showsBranches) {
            BranchSheet(store: store, currentDate: timeline.date(at: playback.time))
        }
        .sheet(isPresented: $showsInspector) {
            if sizeClass == .compact {
                NavigationStack {
                    InspectorPanel(store: store,
                                   snapshot: snapshot,
                                   playback: playback,
                                   selectedItemID: $selectedItemID,
                                   selectedCountryID: $selectedCountryID,
                                   selectedTerritoryID: $selectedTerritoryID)
                        .navigationTitle("Inspector")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Metric.gutterTight) {
            IconButton(systemName: "chevron.left", label: "Back") {
                store.flush()
                dismiss()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(store.project.name)
                    .font(Theme.Font.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(store.project.activeBranchName)
                    .font(Theme.Font.caption)
                    .foregroundStyle(store.project.activeBranchID == nil
                                     ? Theme.Palette.textTertiary : Theme.Palette.gold)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if sizeClass == .regular {
                regularActions
            } else {
                compactActions
            }
        }
        .padding(.horizontal, Theme.Metric.gutterTight)
        .frame(height: Theme.Metric.toolbarHeight)
        .background(Theme.Palette.abyss)
    }

    /// Everything laid out flat, for iPad and landscape where there is room.
    @ViewBuilder
    private var regularActions: some View {
        SaveIndicator(state: store.saveState)

        IconButton(systemName: "arrow.uturn.backward", label: "Undo",
                   tint: store.canUndo ? Theme.Palette.textSecondary : Theme.Palette.textTertiary) {
            store.undo()
        }
        .disabled(!store.canUndo)

        IconButton(systemName: "arrow.uturn.forward", label: "Redo",
                   tint: store.canRedo ? Theme.Palette.textSecondary : Theme.Palette.textTertiary) {
            store.redo()
        }
        .disabled(!store.canRedo)

        IconButton(systemName: "arrow.triangle.branch", label: "Alternate timelines") {
            showsBranches = true
        }
        IconButton(systemName: "wand.and.stars", label: "Auto simulate war") {
            showsSimulator = true
        }
        IconButton(systemName: "sidebar.right", label: "Inspector",
                   isActive: showsInspector) {
            showsInspector.toggle()
        }

        Button("Export") { showsExport = true }
            .buttonStyle(GoldButtonStyle())
    }

    /// On iPhone the flat row needs about 450pt of controls in roughly 390pt of
    /// screen, which pushes the back button off the leading edge and strands the
    /// user in the editor. Everything except undo collapses into a menu.
    @ViewBuilder
    private var compactActions: some View {
        IconButton(systemName: "arrow.uturn.backward", label: "Undo",
                   tint: store.canUndo ? Theme.Palette.textSecondary : Theme.Palette.textTertiary) {
            store.undo()
        }
        .disabled(!store.canUndo)

        Menu {
            Button("Redo", systemImage: "arrow.uturn.forward") { store.redo() }
                .disabled(!store.canRedo)
            Divider()
            Button("Inspector", systemImage: "sidebar.right") { showsInspector = true }
            Button("Alternate timelines", systemImage: "arrow.triangle.branch") {
                showsBranches = true
            }
            Button("Auto simulate war", systemImage: "wand.and.stars") {
                showsSimulator = true
            }
            Divider()
            Button("Export video", systemImage: "square.and.arrow.up") { showsExport = true }
            Divider()
            Text(store.saveState.label)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .accessibilityLabel("More actions")

        Button("Export") { showsExport = true }
            .buttonStyle(GoldButtonStyle())
    }

    // MARK: - Tools

    private var toolRail: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(MapTool.allCases) { candidate in
                    Button {
                        tool = candidate
                        if candidate != .frontline { frontlineDraft = [] }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: candidate.symbolName)
                                .font(.system(size: 15, weight: .medium))
                            Text(candidate.displayName)
                                .font(.system(size: 8, weight: .medium))
                        }
                        .frame(width: Theme.Metric.toolRailWidth - 10, height: 42)
                        .foregroundStyle(tool == candidate
                                         ? Theme.Palette.textOnLight : Theme.Palette.textSecondary)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tool == candidate
                                      ? AnyShapeStyle(Theme.goldLeaf) : AnyShapeStyle(Color.clear))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: Theme.Metric.toolRailWidth)
        .background(Theme.Palette.abyss)
    }

    // MARK: - Map

    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            MapCanvasView(snapshot: snapshot,
                          style: store.project.renderStyle,
                          projection: store.project.projection,
                          countries: store.project.countryIndex,
                          allowsInteraction: !playback.isPlaying,
                          interactiveCamera: $interactiveCamera,
                          onTapTerritory: handleTap)

            VStack(spacing: 6) {
                if !frontlineDraft.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(frontlineDraft.count) points")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Button("Smooth") {
                            frontlineDraft = smoothed(frontlineDraft)
                        }
                        .buttonStyle(GoldButtonStyle(isProminent: false))
                        Button("Finish") { commitFrontline() }
                            .buttonStyle(GoldButtonStyle())
                        Button("Cancel") { frontlineDraft = [] }
                            .buttonStyle(GoldButtonStyle(isProminent: false))
                    }
                }

                HStack(spacing: 10) {
                    Text(tool.hint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    if interactiveCamera != nil {
                        Button("Reset camera") { interactiveCamera = nil }
                            .buttonStyle(GoldButtonStyle(isProminent: false))
                    }
                    if sizeClass == .compact {
                        Menu {
                            ForEach(MapTool.allCases) { candidate in
                                Button(candidate.displayName,
                                       systemImage: candidate.symbolName) { tool = candidate }
                            }
                        } label: {
                            Label(tool.displayName, systemImage: tool.symbolName)
                                .font(Theme.Font.caption)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.abyss.opacity(0.86)))
            }
            .padding(.bottom, Theme.Metric.gutter)
        }
    }

    private func smoothed(_ points: [GeoCoordinate]) -> [GeoCoordinate] {
        let cg = points.map { CGPoint(x: $0.longitude, y: $0.latitude) }
        return Geometry.smooth(cg, iterations: 2)
            .map { GeoCoordinate(longitude: Double($0.x), latitude: Double($0.y)) }
    }

    // MARK: - Tap handling

    private func handleTap(unitID: String, coordinate: GeoCoordinate) {
        selectedTerritoryID = unitID
        let now = playback.time

        switch tool {
        case .select, .country, .zoom, .pan:
            selectedCountryID = snapshot.ownership[unitID]
            if sizeClass == .compact { showsInspector = true }

        case .territory:
            guard let country = selectedCountryID ?? store.project.countries.first?.id else {
                errorMessage = "Choose a country in the inspector first."
                return
            }
            store.addTimelineItem(
                TimelineItem(title: "Capture \(unitID)", start: now, duration: 1.5,
                             easing: .smoothStep,
                             action: .captureTerritory(units: [unitID],
                                                       attacker: country,
                                                       bearing: 90)),
                name: "Capture Territory"
            )

        case .army:
            guard let country = selectedCountryID ?? snapshot.ownership[unitID] else { return }
            let army = Army(name: "\(store.project.countryIndex[country]?.shortName ?? "New") Army",
                            countryID: country, size: 100_000, position: coordinate)
            store.addTimelineItem(
                TimelineItem(title: army.name, start: now, duration: 0,
                             action: .spawnArmy(army)),
                name: "Place Army"
            )

        case .battle:
            let marker = BattleMarker(title: "New Battle",
                                      date: timeline.date(at: now),
                                      coordinate: coordinate,
                                      kind: .battle)
            store.addTimelineItem(
                TimelineItem(title: marker.title, start: now, duration: 2.5,
                             action: .showBattle(marker)),
                name: "Add Battle"
            )

        case .frontline:
            frontlineDraft.append(coordinate)

        case .text:
            store.addTimelineItem(
                TimelineItem(title: "Text", start: now, duration: 3, easing: .easeOut,
                             action: .showText(TextElement(content: "NEW TEXT"))),
                name: "Add Text"
            )

        case .camera:
            let current = interactiveCamera ?? snapshot.camera
            store.addTimelineItem(
                TimelineItem(title: "Camera", start: now, duration: 2.5, easing: .easeInOut,
                             action: .cameraMove(to: current)),
                name: "Add Camera Keyframe"
            )

        case .flag, .city, .arrow:
            // These place an element via the inspector, which needs a selection first.
            selectedCountryID = snapshot.ownership[unitID]
            if sizeClass == .compact { showsInspector = true }

        case .eraser:
            if let selectedItemID {
                store.removeTimelineItem(id: selectedItemID)
                self.selectedItemID = nil
            } else {
                errorMessage = "Select a clip on the timeline to erase it."
            }
        }
    }

    private func commitFrontline() {
        guard frontlineDraft.count >= 2 else {
            frontlineDraft = []
            return
        }
        let attacker = selectedCountryID ?? store.project.countries.first?.id ?? "germany"
        let defender = store.project.countries.first { $0.id != attacker }?.id ?? "ussr"
        let front = Frontline(name: "Front", points: frontlineDraft,
                              attackerID: attacker, defenderID: defender)
        store.addTimelineItem(
            TimelineItem(title: "Front", start: playback.time, duration: 0,
                         action: .showFrontline(front)),
            name: "Draw Frontline"
        )
        frontlineDraft = []
    }
}
