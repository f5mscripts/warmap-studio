import SwiftUI

/// The multi-track timeline along the bottom of the editor.
///
/// Clips can be dragged along their lane; the ruler shows historical dates rather
/// than video seconds, because that is what the user is actually editing against.
struct TimelineView: View {

    @ObservedObject var store: EditorStore
    @ObservedObject var playback: PlaybackController
    @Binding var selectedItemID: UUID?

    /// Horizontal points per second of video.
    @State private var pixelsPerSecond: CGFloat = 34
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0

    private var timeline: Timeline { store.project.activeTimeline }
    private let laneHeight: CGFloat = 26
    private let labelWidth: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            transportBar
            Divider().overlay(Theme.Palette.rule)
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 0) {
                    laneLabels
                    ZStack(alignment: .topLeading) {
                        lanes
                        playhead
                    }
                    .frame(width: max(contentWidth, 200))
                }
            }
            .background(Theme.Palette.charcoal)
        }
        .background(Theme.Palette.abyss)
    }

    private var contentWidth: CGFloat {
        CGFloat(timeline.duration) * pixelsPerSecond + 40
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: Theme.Metric.gutterTight) {
            IconButton(systemName: "backward.end.fill", label: "Rewind to start") {
                playback.rewindToStart()
            }
            IconButton(systemName: "gobackward.5", label: "Back 5 seconds") {
                playback.step(by: -5)
            }
            IconButton(systemName: playback.isPlaying ? "pause.fill" : "play.fill",
                       label: playback.isPlaying ? "Pause" : "Play",
                       tint: Theme.Palette.gold) {
                playback.togglePlayPause()
            }
            IconButton(systemName: "goforward.5", label: "Forward 5 seconds") {
                playback.step(by: 5)
            }

            Menu {
                ForEach(PlaybackController.speedOptions, id: \.self) { option in
                    Button {
                        playback.speed = option
                    } label: {
                        Label("\(option, format: .number)×",
                              systemImage: playback.speed == option ? "checkmark" : "")
                    }
                }
                Divider()
                Toggle("Loop", isOn: $playback.loops)
            } label: {
                Text("\(playback.speed, format: .number)×")
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 42, height: 30)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.Palette.graphite))
            }

            Divider().frame(height: 20).overlay(Theme.Palette.rule)

            Text(timeline.date(at: playback.time).formatted(store.project.dateFormat))
                .font(Theme.Font.mono(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.gold)
                .frame(minWidth: 160, alignment: .leading)

            Text(String(format: "%.1fs / %.0fs", playback.time, timeline.duration))
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Palette.textTertiary)

            Spacer()

            IconButton(systemName: "minus.magnifyingglass", label: "Zoom out timeline") {
                pixelsPerSecond = max(8, pixelsPerSecond / 1.4)
            }
            IconButton(systemName: "plus.magnifyingglass", label: "Zoom in timeline") {
                pixelsPerSecond = min(220, pixelsPerSecond * 1.4)
            }
        }
        .padding(.horizontal, Theme.Metric.gutterTight)
        .frame(height: 42)
    }

    // MARK: - Lanes

    private var laneLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 22)  // aligns with the ruler
            ForEach(TrackKind.allCases) { track in
                HStack(spacing: 5) {
                    Image(systemName: track.symbolName)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hexString: track.tintHex) ?? Theme.Palette.textTertiary)
                    Text(track.displayName)
                        .font(Theme.Font.ui(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: labelWidth, height: laneHeight, alignment: .leading)
            }
        }
        .background(Theme.Palette.abyss)
    }

    private var lanes: some View {
        VStack(alignment: .leading, spacing: 2) {
            ruler
            ForEach(TrackKind.allCases) { track in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Theme.Palette.slate.opacity(0.5))
                        .frame(height: laneHeight)
                    ForEach(timeline.items(on: track)) { item in
                        clip(item)
                    }
                }
                .frame(height: laneHeight)
            }
        }
    }

    /// Date ticks. The spacing adapts so labels never collide at any zoom.
    private var ruler: some View {
        let range = timeline.historicalRange
        let totalYears = max(1.0, range.end.years(since: range.start))
        let pointsPerYear = CGFloat(timeline.duration) * pixelsPerSecond / CGFloat(totalYears)
        let yearStep = max(1, Int((70 / max(pointsPerYear, 0.001)).rounded(.up)))

        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.Palette.abyss).frame(height: 22)
            ForEach(tickYears(step: yearStep), id: \.self) { year in
                let tickDate = HistoricalDate(year: year)
                let x = CGFloat(timeline.time(for: tickDate)) * pixelsPerSecond
                VStack(alignment: .leading, spacing: 1) {
                    Text(tickDate.tickLabel)
                        .font(Theme.Font.mono(9))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Rectangle()
                        .fill(Theme.Palette.rule)
                        .frame(width: 1, height: 6)
                }
                .offset(x: x)
            }
        }
        .frame(height: 22)
    }

    private func tickYears(step: Int) -> [Int] {
        let range = timeline.historicalRange
        let first = range.start.year
        let last = range.end.year
        guard last >= first else { return [first] }
        return stride(from: first, through: last, by: step).map { $0 }
    }

    private func clip(_ item: TimelineItem) -> some View {
        let x = CGFloat(item.start) * pixelsPerSecond
            + (draggingID == item.id ? dragOffset : 0)
        let width = max(CGFloat(item.duration) * pixelsPerSecond, 8)
        let tint = Color(hexString: item.track.tintHex) ?? Theme.Palette.gold
        let isSelected = selectedItemID == item.id

        return RoundedRectangle(cornerRadius: 3)
            .fill(tint.opacity(item.isEnabled ? 0.55 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isSelected ? Theme.Palette.goldBright : tint.opacity(0.9),
                                  lineWidth: isSelected ? 1.6 : 0.8)
            )
            .overlay(alignment: .leading) {
                Text(item.title)
                    .font(Theme.Font.ui(9, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: laneHeight - 6)
            .offset(x: x, y: 3)
            .onTapGesture { selectedItemID = item.id }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        draggingID = item.id
                        dragOffset = value.translation.width
                        selectedItemID = item.id
                    }
                    .onEnded { value in
                        let delta = TimeInterval(value.translation.width / pixelsPerSecond)
                        store.moveTimelineItem(id: item.id, to: item.start + delta)
                        draggingID = nil
                        dragOffset = 0
                    }
            )
    }

    private var playhead: some View {
        let x = CGFloat(playback.time) * pixelsPerSecond
        return Rectangle()
            .fill(Theme.Palette.goldBright)
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                Triangle()
                    .fill(Theme.Palette.goldBright)
                    .frame(width: 9, height: 6)
                    .offset(y: -1)
            }
            .offset(x: x)
            .allowsHitTesting(false)
    }
}

/// The playhead's little downward-pointing marker.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
