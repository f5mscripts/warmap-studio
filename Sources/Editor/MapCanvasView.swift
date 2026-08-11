import SwiftUI

/// The live map.
///
/// Draws through the same `MapSceneRenderer` the exporter uses, inside a SwiftUI
/// `Canvas`. Gestures adjust the camera unless the timeline is driving it, so a
/// scrubbed camera keyframe and a finger drag never fight over the same value.
struct MapCanvasView: View {

    let snapshot: WorldSnapshot
    let style: MapRenderStyle
    let projection: MapProjectionKind
    let countries: [String: Country]
    /// When true, gestures move the camera; when false the timeline owns it.
    var allowsInteraction: Bool = true
    /// Camera the user has panned to, overriding the snapshot's.
    @Binding var interactiveCamera: MapCamera?
    /// Reports a tap on a territory, for the select and paint tools.
    var onTapTerritory: ((String, GeoCoordinate) -> Void)?

    @State private var renderer = MapSceneRenderer()
    @State private var gestureAnchor: MapCamera?
    @State private var renderFailure: String?

    private var camera: MapCamera { interactiveCamera ?? snapshot.camera }

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let transform = MapTransform(projection: projection,
                                         camera: camera,
                                         viewport: viewport)
            ZStack {
                Canvas(rendersAsynchronously: false) { context, size in
                    context.withCGContext { cgContext in
                        do {
                            try renderer.render(snapshot,
                                                transform: MapTransform(projection: projection,
                                                                        camera: camera,
                                                                        viewport: size),
                                                style: style,
                                                countries: countries,
                                                into: cgContext)
                        } catch {
                            // A failed frame must not take the app down: report it
                            // once and leave the last good frame on screen.
                            Task { @MainActor in
                                renderFailure = error.localizedDescription
                            }
                        }
                    }
                }
                .drawingGroup()

                if let renderFailure {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.warning)
                        Text("The map could not be drawn")
                            .font(Theme.Font.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(renderFailure)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Theme.Palette.slate.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner))
                    .padding()
                }
            }
            .contentShape(Rectangle())
            .gesture(allowsInteraction ? dragGesture(viewport: viewport) : nil)
            .gesture(allowsInteraction ? magnifyGesture : nil)
            .onTapGesture { location in
                guard let onTapTerritory else { return }
                let coordinate = transform.coordinate(for: location)
                if let unit = territory(at: coordinate) {
                    onTapTerritory(unit, coordinate)
                }
            }
        }
    }

    // MARK: - Gestures

    private func dragGesture(viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let anchor = gestureAnchor ?? camera
                if gestureAnchor == nil { gestureAnchor = anchor }

                // Convert the drag in points into a shift in projection units, so
                // the land under the finger stays under the finger at any zoom.
                let scale = viewport.width > 0 ? Double(viewport.width) / anchor.span : 1
                let dx = Double(value.translation.width) / scale
                let dy = Double(value.translation.height) / scale

                let projected = projection.project(anchor.center)
                let moved = ProjectedPoint(x: projected.x - dx, y: projected.y + dy)
                var updated = anchor
                updated.center = projection.unproject(moved)
                interactiveCamera = updated
            }
            .onEnded { _ in gestureAnchor = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = gestureAnchor ?? camera
                if gestureAnchor == nil { gestureAnchor = anchor }
                var updated = anchor
                updated.span = min(max(anchor.span / value.magnification,
                                       MapCamera.minimumSpan), MapCamera.maximumSpan)
                interactiveCamera = updated
            }
            .onEnded { _ in gestureAnchor = nil }
    }

    /// Finds which territory a coordinate falls in.
    ///
    /// Uses the bounding box to narrow the field, then an exact point-in-polygon
    /// test — a bounding-box-only hit would pick Russia for half of Europe.
    private func territory(at coordinate: GeoCoordinate) -> String? {
        guard let units = try? MapLibrary.shared.units(),
              let geometry = try? MapLibrary.shared.geometry(lod: .medium) else { return nil }

        let candidates = units.filter { $0.bounds.contains(coordinate) }
        let point = CGPoint(x: coordinate.longitude, y: coordinate.latitude)

        for unit in candidates.sorted(by: { $0.area < $1.area }) {
            guard let multi = geometry[unit.id] else { continue }
            for polygon in multi.polygons {
                let ring = polygon.exterior.map { CGPoint(x: $0.longitude, y: $0.latitude) }
                if Geometry.contains(ring, point: point) {
                    return unit.id
                }
            }
        }
        // Smallest containing box is a decent fallback for islands the simplified
        // outline has shrunk away from the tap.
        return candidates.min(by: { $0.area < $1.area })?.id
    }
}
