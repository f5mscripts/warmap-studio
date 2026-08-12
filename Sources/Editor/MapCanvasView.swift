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
    /// Reports a tap on the map. The unit id is nil for open sea, which is what
    /// lets a fleet or an air wing be placed where there is no land.
    var onTapMap: ((String?, GeoCoordinate) -> Void)?

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
            // `.gesture` takes a concrete gesture, not an optional, so interaction is
            // switched off through the mask rather than by omitting the modifier.
            .gesture(dragGesture(viewport: viewport),
                     including: allowsInteraction ? .all : .subviews)
            .gesture(magnifyGesture,
                     including: allowsInteraction ? .all : .subviews)
            .onTapGesture { location in
                guard let onTapMap else { return }
                let coordinate = transform.coordinate(for: location)
                onTapMap(territory(at: coordinate), coordinate)
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

    /// Finds which territory a coordinate falls in, or nil for open sea.
    ///
    /// Bounding boxes narrow the field and an exact point-in-polygon test decides —
    /// a box-only hit would pick Russia for half of Europe. The one concession is
    /// for islands small enough that simplification has pulled their outline away
    /// from where they are drawn; for those, and only those, the box is accepted.
    ///
    /// Everything else returns nil rather than snapping to whichever country's box
    /// happens to cover that stretch of water. Norway's box reaches most of the
    /// Norwegian Sea, and a destroyer dropped there belongs at sea, not in Norway.
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
        let islands = candidates.filter { unit in
            unit.bounds.maxLongitude - unit.bounds.minLongitude < Self.islandSpan
                && unit.bounds.maxLatitude - unit.bounds.minLatitude < Self.islandSpan
        }
        return islands.min(by: { $0.area < $1.area })?.id
    }

    /// How wide a territory's box may be, in degrees, before it stops counting as a
    /// small island that the polygon test can reasonably miss.
    private static let islandSpan: Double = 2
}
