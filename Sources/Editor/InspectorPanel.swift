import SwiftUI

/// Context-sensitive properties for whatever is selected.
struct InspectorPanel: View {

    @ObservedObject var store: EditorStore
    let snapshot: WorldSnapshot
    @ObservedObject var playback: PlaybackController
    @Binding var selectedItemID: UUID?
    @Binding var selectedCountryID: String?
    @Binding var selectedTerritoryID: String?

    private var timeline: Timeline { store.project.activeTimeline }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metric.gutter) {
                if let item = timeline.items.first(where: { $0.id == selectedItemID }) {
                    clipSection(item)
                }
                territorySection
                countriesSection
                eventsSection
                appearanceSection
            }
            .padding(Theme.Metric.gutter)
        }
        .background(Theme.Palette.charcoal)
    }

    // MARK: - Clip

    private func clipSection(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
            SectionHeader("SELECTED CLIP")
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(item.track.displayName)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Color(hexString: item.track.tintHex) ?? .gray)

                    LabeledSlider(title: "Start",
                                  value: Binding(
                                    get: { item.start },
                                    set: { store.moveTimelineItem(id: item.id, to: $0) }),
                                  range: 0...max(timeline.duration, 1),
                                  format: "%.1fs")

                    LabeledSlider(title: "Duration",
                                  value: Binding(
                                    get: { item.duration },
                                    set: { newValue in
                                        var updated = item
                                        updated.duration = newValue
                                        store.updateTimelineItem(updated)
                                    }),
                                  range: 0...20,
                                  format: "%.1fs")

                    Picker("Easing", selection: Binding(
                        get: { item.easing },
                        set: { newValue in
                            var updated = item
                            updated.easing = newValue
                            store.updateTimelineItem(updated)
                        })) {
                        ForEach(EasingCurve.allCases) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    .font(Theme.Font.caption)

                    Toggle("Enabled", isOn: Binding(
                        get: { item.isEnabled },
                        set: { newValue in
                            var updated = item
                            updated.isEnabled = newValue
                            store.updateTimelineItem(updated)
                        }))
                    .font(Theme.Font.caption)

                    HStack {
                        Button("Go to clip") { playback.seek(to: item.start) }
                            .buttonStyle(GoldButtonStyle(isProminent: false))
                        Button(role: .destructive) {
                            store.removeTimelineItem(id: item.id)
                            selectedItemID = nil
                        } label: {
                            Text("Delete")
                        }
                        .buttonStyle(GoldButtonStyle(isProminent: false))
                    }
                }
            }
        }
    }

    // MARK: - Territory

    @ViewBuilder
    private var territorySection: some View {
        if let territoryID = selectedTerritoryID {
            VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
                SectionHeader("TERRITORY")
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(territoryName(territoryID))
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(territoryID)
                            .font(Theme.Font.mono(11))
                            .foregroundStyle(Theme.Palette.textTertiary)

                        if let owner = snapshot.ownership[territoryID],
                           let country = store.project.countryIndex[owner] {
                            HStack(spacing: 6) {
                                Text("Held by")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                CountryChip(country: country, date: snapshot.date)
                            }
                        }

                        if let contest = snapshot.contested[territoryID] {
                            Text("Under attack — \(Int(contest.progress * 100))% taken")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.warning)
                        }

                        if let selectedCountryID {
                            Button("Give to \(store.project.countryIndex[selectedCountryID]?.name ?? selectedCountryID)") {
                                store.setTerritoryOwner(territoryID, to: selectedCountryID)
                            }
                            .buttonStyle(GoldButtonStyle(isProminent: false))
                        }
                    }
                }
            }
        }
    }

    private func territoryName(_ id: String) -> String {
        (try? MapLibrary.shared.unit(id))??.name ?? id
    }

    // MARK: - Countries

    private var countriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
            SectionHeader("COUNTRIES") {
                Text("\(store.project.countries.count)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            VStack(spacing: 5) {
                ForEach(store.project.countries) { country in
                    Button {
                        selectedCountryID = country.id
                    } label: {
                        HStack {
                            CountryChip(country: country,
                                        date: snapshot.date,
                                        isSelected: selectedCountryID == country.id)
                            Spacer()
                            Text("\(snapshot.territoryCounts()[country.id] ?? 0)")
                                .font(Theme.Font.mono(11))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsSection: some View {
        let events = snapshot.recentEvents.prefix(8)
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
                SectionHeader("EVENTS")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(events)) { event in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: event.kind.symbolName)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hexString: event.kind.tintHex) ?? .gray)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(Theme.Font.ui(12, weight: .medium))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text(event.date.formatted(store.project.dateFormat))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gutterTight) {
            SectionHeader("APPEARANCE")
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Map style", selection: Binding(
                        get: { store.project.mapStyle },
                        set: { store.setMapStyle($0) })) {
                        ForEach(MapStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Picker("Projection", selection: Binding(
                        get: { store.project.projection },
                        set: { newValue in
                            store.apply("Change Projection") { $0.projection = newValue }
                        })) {
                        ForEach(MapProjectionKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Picker("Date format", selection: Binding(
                        get: { store.project.dateFormat },
                        set: { newValue in
                            store.apply("Change Date Format") { $0.dateFormat = newValue }
                        })) {
                        ForEach(HistoricalDate.Format.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Toggle("Show cities", isOn: Binding(
                        get: { store.project.renderStyle.showsCities },
                        set: { newValue in
                            store.apply("Toggle Cities") { $0.renderStyle.showsCities = newValue }
                        }))
                    Toggle("Capitals only", isOn: Binding(
                        get: { store.project.renderStyle.showsCapitalsOnly },
                        set: { newValue in
                            store.apply("Toggle Capitals") {
                                $0.renderStyle.showsCapitalsOnly = newValue
                            }
                        }))
                    Toggle("Country labels", isOn: Binding(
                        get: { store.project.renderStyle.showsCountryLabels },
                        set: { newValue in
                            store.apply("Toggle Labels") {
                                $0.renderStyle.showsCountryLabels = newValue
                            }
                        }))
                }
                .font(Theme.Font.caption)
            }
        }
    }
}

/// A slider with its value shown alongside.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(String(format: format, value))
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Slider(value: $value, in: range)
                .tint(Theme.Palette.gold)
        }
    }
}
