import CoreGraphics
import CoreText
import Foundation

/// Draws a `WorldSnapshot` into a `CGContext`.
///
/// This is the single drawing path in the app. The live editor hands it a
/// `CGContext` from a `CALayer`; the exporter hands it a bitmap context backing a
/// `CVPixelBuffer`. Same snapshot plus same transform gives the same pixels, which
/// is the whole reason preview and export cannot drift apart.
///
/// Nothing here mutates state or reads a clock — every frame is drawn purely from
/// its arguments.
public final class MapSceneRenderer {

    private let library: MapLibrary
    private let pathCache: TerritoryPathCache
    /// Country colours, resolved once per render rather than looked up per territory.
    private var colorCache: [String: CGColor] = [:]
    /// Set for the duration of a pixel-style render, so every stray colour in the
    /// scene lands on the palette too — not just the country fills.
    private var quantisesColors = false

    public init(library: MapLibrary = .shared,
                pathCache: TerritoryPathCache? = nil) {
        self.library = library
        self.pathCache = pathCache ?? TerritoryPathCache(library: library)
    }

    /// Draws one frame.
    ///
    /// - Parameter countries: the project's country list, used for fill colours,
    ///   labels and flags. Passed in rather than read from a global so an alternate
    ///   -history branch can recolour the world without touching the catalogue.
    public func render(_ snapshot: WorldSnapshot,
                       transform: MapTransform,
                       style: MapRenderStyle,
                       countries: [String: Country],
                       into context: CGContext) throws {
        guard style.isPixelated,
              let buffer = PixelGrid.buffer(for: transform.viewport,
                                            shortEdge: style.pixelShortEdge) else {
            try drawScene(snapshot, transform: transform, style: style,
                          countries: countries, pixel: nil, into: context)
            return
        }
        try renderPixelated(snapshot, transform: transform, style: style,
                            countries: countries, buffer: buffer, into: context)
    }

    /// The pixel-art path: draw the frame small, then blow it up.
    ///
    /// The scene is rendered into an offscreen buffer a couple of hundred pixels
    /// across — through a transform built for *that* viewport, so the camera frames
    /// exactly the same land — and the result is drawn into the output context at a
    /// whole-number scale with interpolation off. Every buffer pixel becomes a hard
    /// square block. Nothing downstream fakes the look by drawing large rectangles;
    /// the blocks are real pixels, which is why labels, coastlines and sprites all
    /// land on the same grid instead of only the parts somebody remembered to
    /// chunk up.
    private func renderPixelated(_ snapshot: WorldSnapshot,
                                 transform: MapTransform,
                                 style: MapRenderStyle,
                                 countries: [String: Country],
                                 buffer: PixelGrid.Buffer,
                                 into context: CGContext) throws {
        guard let low = CGContext(data: nil,
                                  width: Int(buffer.size.width),
                                  height: Int(buffer.size.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw WarMapError.renderFailed(detail: "the low-resolution buffer could not be allocated")
        }

        // Bitmap contexts are y-up. The renderer works y-down like every other
        // coordinate in the app, so flip once here rather than in each layer.
        low.translateBy(x: 0, y: buffer.size.height)
        low.scaleBy(x: 1, y: -1)
        low.setShouldAntialias(false)
        low.setAllowsAntialiasing(false)
        low.setShouldSmoothFonts(false)
        low.setAllowsFontSmoothing(false)
        low.interpolationQuality = .none

        let lowTransform = MapTransform(projection: transform.projection,
                                        camera: transform.camera,
                                        viewport: buffer.size)
        try drawScene(snapshot, transform: lowTransform, style: style, countries: countries,
                      pixel: PixelPass(scale: buffer.scale), into: low)

        guard let image = low.makeImage() else {
            throw WarMapError.renderFailed(detail: "the low-resolution buffer produced no image")
        }

        context.saveGState()
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        // Images draw bottom-up, and the destination is already flipped to y-down,
        // so flipping a second time puts the buffer back the right way round.
        let output = buffer.outputSize
        context.translateBy(x: 0, y: output.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: output))
        context.restoreGState()
    }

    /// Draws every layer of the map, in order, into whatever context it is given.
    ///
    /// `pixel` is non-nil only on the low-resolution pass, where it carries the
    /// upscale factor so each layer can size itself in buffer pixels.
    private func drawScene(_ snapshot: WorldSnapshot,
                           transform: MapTransform,
                           style: MapRenderStyle,
                           countries: [String: Country],
                           pixel: PixelPass?,
                           into context: CGContext) throws {

        let lod = LevelOfDetail.forUnitsPerPoint(transform.unitsPerPoint)
        let projection = transform.projection
        let affine = transform.projectedToScreen
        let visible = transform.visibleProjectedRect

        prepareColors(for: countries, style: style)

        drawOcean(style: style, transform: transform, pixel: pixel, context: context)
        if style.showsGraticule {
            drawGraticule(style: style, transform: transform, context: context)
        }

        let geometry = try library.geometry(lod: lod)
        let units = try library.units()

        // 1. Territory fills.
        for unit in units {
            guard geometry[unit.id] != nil,
                  let cached = try pathCache.territoryPath(unitID: unit.id, lod: lod,
                                                           projection: projection),
                  cached.bounds.intersects(visible) else { continue }

            let owner = snapshot.ownership[unit.id]
            let fill = owner.flatMap { colorCache[$0] } ?? color(style.neutralLandHex)
            fillPath(cached.path, with: fill, alpha: style.territoryOpacity,
                     affine: affine, pixel: pixel, context: context)
        }

        // 2. Territory currently being taken: the attacker's colour sweeps across.
        for (unitID, contest) in snapshot.contested.sorted(by: { $0.key < $1.key }) {
            guard let cached = try pathCache.territoryPath(unitID: unitID, lod: lod,
                                                           projection: projection),
                  cached.bounds.intersects(visible),
                  let attackerColor = colorCache[contest.attackerID] else { continue }
            drawCapture(cached: cached, contest: contest, color: attackerColor,
                        style: style, transform: transform, pixel: pixel, context: context)
        }

        // 3. Borders. Drawn from the shared-edge table so a seam between two units of
        //    the same country stays invisible.
        try drawBorders(snapshot: snapshot, lod: lod, style: style,
                        transform: transform, pixel: pixel, context: context)

        // 4. Frontlines and their advance arrows.
        for frontline in snapshot.frontlines {
            drawFrontline(frontline, countries: countries, transform: transform,
                          pixel: pixel, context: context)
        }

        // 5. Cities.
        if style.showsCities {
            try drawCities(snapshot: snapshot, style: style, transform: transform,
                           pixel: pixel, context: context)
        }

        // 6. Country labels.
        if style.showsCountryLabels {
            try drawCountryLabels(snapshot: snapshot, countries: countries, style: style,
                                  transform: transform, pixel: pixel, context: context)
        }

        // 7. Armies.
        for army in snapshot.armies {
            drawArmy(army, countries: countries, style: style, transform: transform,
                     pixel: pixel, context: context)
        }

        // 8. Battle markers.
        for battle in snapshot.battles {
            drawBattle(battle, style: style, transform: transform, pixel: pixel,
                       context: context)
        }

        // 9. Text last, so nothing draws over a title.
        for text in snapshot.texts {
            drawText(text, viewport: transform.viewport, pixel: pixel, context: context)
        }
    }

    // MARK: - Colours

    private func prepareColors(for countries: [String: Country], style: MapRenderStyle) {
        colorCache.removeAll(keepingCapacity: true)
        quantisesColors = style.isPixelated

        guard style.isPixelated else {
            for (id, country) in countries {
                colorCache[id] = FlagRenderer.cgColor(country.colorHex)
            }
            return
        }
        // The whole cast is quantised together rather than country by country, so two
        // near-identical reds are pushed onto different palette entries instead of
        // becoming the same side at 200 pixels across.
        for (id, hex) in PixelPalette.factionColors(for: countries.mapValues(\.colorHex)) {
            colorCache[id] = FlagRenderer.cgColor(hex)
        }
    }

    private func color(_ hex: String) -> CGColor {
        quantisesColors ? PixelPalette.cgColor(hex) : FlagRenderer.cgColor(hex)
    }

    // MARK: - Layers

    private func drawOcean(style: MapRenderStyle, transform: MapTransform,
                           pixel: PixelPass?, context: CGContext) {
        let rect = CGRect(origin: .zero, size: transform.viewport)

        // A gradient interpolates, and every step between two palette entries is a
        // colour that is in neither. The pixel sea is flat.
        if pixel != nil {
            context.setFillColor(color(style.oceanHex))
            context.fill(rect)
            return
        }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [color(style.oceanHex),
                                                 color(style.oceanDeepHex)] as CFArray,
                                        locations: [0, 1]) else {
            context.setFillColor(color(style.oceanHex))
            context.fill(rect)
            return
        }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.midX, y: rect.minY),
                                   end: CGPoint(x: rect.midX, y: rect.maxY),
                                   options: [])
        context.restoreGState()
    }

    /// Meridians and parallels at a spacing chosen from the zoom, so a world view
    /// gets 30° lines and a close-up gets 1°.
    private func drawGraticule(style: MapRenderStyle, transform: MapTransform, context: CGContext) {
        let span = transform.camera.span
        let step: Double
        switch span {
        case ..<3: step = 1
        case ..<10: step = 2
        case ..<30: step = 5
        case ..<90: step = 10
        default: step = 30
        }

        context.saveGState()
        context.setStrokeColor(color(style.graticuleHex))
        context.setLineWidth(0.6)
        let bounds = transform.visibleBounds

        var lon = (bounds.minLongitude / step).rounded(.down) * step
        while lon <= bounds.maxLongitude {
            let path = CGMutablePath()
            var first = true
            var lat = max(bounds.minLatitude, -85.0)
            while lat <= min(bounds.maxLatitude, 85.0) {
                let p = transform.point(for: GeoCoordinate(longitude: lon, latitude: lat))
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
                lat += step / 4
            }
            context.addPath(path)
            lon += step
        }

        var lat = (bounds.minLatitude / step).rounded(.down) * step
        while lat <= bounds.maxLatitude {
            guard abs(lat) <= 85 else { lat += step; continue }
            let path = CGMutablePath()
            let a = transform.point(for: GeoCoordinate(longitude: bounds.minLongitude, latitude: lat))
            let b = transform.point(for: GeoCoordinate(longitude: bounds.maxLongitude, latitude: lat))
            path.move(to: a)
            path.addLine(to: b)
            context.addPath(path)
            lat += step
        }

        context.strokePath()
        context.restoreGState()
    }

    private func fillPath(_ path: CGPath, with color: CGColor, alpha: Double,
                          affine: CGAffineTransform, pixel: PixelPass?, context: CGContext) {
        context.saveGState()
        context.setAlpha(CGFloat(alpha))
        context.setFillColor(color)
        var transform = affine
        if let transformed = path.copy(using: &transform) {
            // Snapping the screen-space outline is what tiles a coastline: without it
            // the polygon edge crosses pixel centres at arbitrary points along a run,
            // and the upscaled edge comes out as a ragged staircase rather than a
            // deliberate one.
            context.addPath(pixel == nil ? transformed : PixelGrid.snap(transformed))
            // Even-odd punches holes out for lakes and enclaves, which are appended
            // as extra subpaths rather than reversed rings.
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
    }

    /// Paints the captured fraction of a contested territory.
    ///
    /// Rather than clipping the territory polygon itself, this clips the *context* to
    /// the territory and then fills a half-plane across it. Core Graphics does the
    /// intersection in hardware, so an advancing front costs one fill per territory
    /// per frame no matter how intricate its coastline.
    private func drawCapture(cached: TerritoryPathCache.CachedPath,
                             contest: ContestedTerritory,
                             color: CGColor,
                             style: MapRenderStyle,
                             transform: MapTransform,
                             pixel: PixelPass?,
                             context: CGContext) {
        guard contest.progress > 0 else { return }

        var affine = transform.projectedToScreen
        guard let copied = cached.path.copy(using: &affine) else { return }
        let screenPath = pixel == nil ? copied : PixelGrid.snap(copied)
        let box = screenPath.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return }

        // Compass bearing to a screen-space direction, accounting for camera
        // rotation: 0° is north (up the screen), 90° is east (to the right).
        let radians = contest.bearing * .pi / 180 + transform.camera.rotation
        let direction = CGVector(dx: sin(radians), dy: -cos(radians))
        let (sweep, normal) = Geometry.sweepHalfPlane(bounds: box,
                                                      direction: direction,
                                                      progress: contest.progress)
        // Put the advancing edge on the grid too, so a front creeps across a
        // territory a whole pixel at a time rather than dissolving into it.
        let origin = pixel == nil ? sweep : PixelGrid.snap(sweep)

        context.saveGState()
        context.addPath(screenPath)
        context.clip(using: .evenOdd)

        context.setFillColor(color)
        context.setAlpha(CGFloat(style.territoryOpacity))
        context.addPath(Self.halfPlanePath(origin: origin, normal: normal, covering: box))
        context.fillPath()

        // A bright leading edge sells the advance, especially between two similar
        // faction colours.
        if style.contestedHighlight > 0, contest.progress < 1 {
            if pixel == nil {
                context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1,
                                               alpha: CGFloat(style.contestedHighlight)))
            } else {
                // A translucent white would blend into a colour the palette does not
                // contain, so the pixel edge is opaque paper instead.
                context.setStrokeColor(FlagRenderer.cgColor(PixelPalette.paper))
            }
            context.setLineWidth(2)
            let perpendicular = CGVector(dx: -normal.dy, dy: normal.dx)
            let reach = max(box.width, box.height) * 2
            context.beginPath()
            context.move(to: CGPoint(x: origin.x - perpendicular.dx * reach,
                                     y: origin.y - perpendicular.dy * reach))
            context.addLine(to: CGPoint(x: origin.x + perpendicular.dx * reach,
                                        y: origin.y + perpendicular.dy * reach))
            context.strokePath()
        }

        context.restoreGState()
    }

    /// A quad large enough to cover the kept side of a half-plane over `box`.
    static func halfPlanePath(origin: CGPoint, normal: CGVector, covering box: CGRect) -> CGPath {
        let reach = max(box.width, box.height) * 4 + 64
        let perpendicular = CGVector(dx: -normal.dy, dy: normal.dx)
        let path = CGMutablePath()
        let a = CGPoint(x: origin.x + perpendicular.dx * reach,
                        y: origin.y + perpendicular.dy * reach)
        let b = CGPoint(x: origin.x - perpendicular.dx * reach,
                        y: origin.y - perpendicular.dy * reach)
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: b.x + normal.dx * reach, y: b.y + normal.dy * reach))
        path.addLine(to: CGPoint(x: a.x + normal.dx * reach, y: a.y + normal.dy * reach))
        path.closeSubpath()
        return path
    }

    private func drawBorders(snapshot: WorldSnapshot,
                             lod: LevelOfDetail,
                             style: MapRenderStyle,
                             transform: MapTransform,
                             pixel: PixelPass?,
                             context: CGContext) throws {
        let borders = try library.borders(lod: lod)
        let visible = transform.visibleBounds
        var affine = transform.projectedToScreen

        let coastPath = CGMutablePath()
        let politicalPath = CGMutablePath()
        // Half a pixel for an odd stroke width, so a one-pixel border covers one
        // pixel rather than half-lighting the two either side of the grid line.
        let coastOffset = PixelGrid.lineOffset(forWidth: CGFloat(style.coastlineWidth))
        let politicalOffset = PixelGrid.lineOffset(forWidth: CGFloat(style.borderWidth))

        for (index, segment) in borders.enumerated() {
            guard segment.bounds.intersects(visible) else { continue }

            if let other = segment.b {
                // Same power on both sides means this is an internal seam, not a
                // border — the mechanism that lets a partitioned country look whole
                // again once it is reunified.
                let ownerA = snapshot.ownership[segment.a]
                let ownerB = snapshot.ownership[other]
                guard ownerA != ownerB else { continue }
            }

            let cached = pathCache.borderPath(index: index, segment: segment,
                                              lod: lod, projection: transform.projection)
            guard let transformed = cached.path.copy(using: &affine) else { continue }
            if segment.isCoastline {
                coastPath.addPath(pixel == nil ? transformed
                                               : PixelGrid.snap(transformed, offset: coastOffset))
            } else {
                politicalPath.addPath(pixel == nil ? transformed
                                                   : PixelGrid.snap(transformed, offset: politicalOffset))
            }
        }

        context.saveGState()
        // Round joins spread a stroke over neighbouring pixels; square ones keep a
        // two-pixel border exactly two pixels wide all the way round a corner.
        context.setLineJoin(pixel == nil ? .round : .miter)
        context.setLineCap(pixel == nil ? .round : .square)

        if !coastPath.isEmpty {
            context.setStrokeColor(color(style.coastlineHex))
            context.setLineWidth(CGFloat(style.coastlineWidth))
            context.addPath(coastPath)
            context.strokePath()
        }
        if !politicalPath.isEmpty {
            context.setStrokeColor(color(style.borderHex))
            context.setLineWidth(CGFloat(style.borderWidth))
            context.addPath(politicalPath)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawFrontline(_ frontline: Frontline,
                               countries: [String: Country],
                               transform: MapTransform,
                               pixel: PixelPass?,
                               context: CGContext) {
        var points = frontline.points.map { transform.point(for: $0) }
        guard points.count >= 2 else { return }

        let tint = colorCache[frontline.attackerID]
            ?? CGColor(red: 0.7, green: 0.26, blue: 0.23, alpha: 1)
        let authored = CGFloat(frontline.thickness)
        let thickness = pixel.map { $0.size(authored, minimum: 2) } ?? authored

        if pixel != nil {
            let offset = PixelGrid.lineOffset(forWidth: thickness)
            points = points.map { PixelGrid.snap($0, offset: offset) }
        }

        context.saveGState()
        context.setLineJoin(pixel == nil ? .round : .miter)
        context.setLineCap(pixel == nil ? .round : .square)
        context.setStrokeColor(tint)
        context.setLineWidth(thickness)

        switch frontline.style {
        case .dashed:
            let dash: [CGFloat] = pixel == nil ? [8, 6] : [4, 3]
            context.setLineDash(phase: 0, lengths: dash)
        case .gradient:
            // Translucency is off the palette, so the pixel style says "pressure"
            // with a fatter opaque line instead.
            if pixel == nil { context.setAlpha(0.75) }
            context.setLineWidth(thickness * 2.5)
        case .solid, .toothed:
            break
        }

        let path = CGMutablePath()
        path.addLines(between: points)
        context.addPath(path)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        if frontline.style == .toothed {
            drawTeeth(along: points, tint: tint, size: pixel == nil ? 5 : 3, context: context)
        }

        if frontline.showsArrows {
            let length: CGFloat = pixel.map { $0.size(26, minimum: 6) } ?? 26
            for fraction in frontline.arrowPositions {
                guard let sample = Geometry.pointAlong(points, fraction: fraction) else { continue }
                // Arrows point across the front, into the defender's side.
                let across = CGVector(dx: sample.direction.dy, dy: -sample.direction.dx)
                drawArrow(at: sample.point, direction: across, length: length, tint: tint,
                          width: pixel == nil ? 3 : 2, context: context)
            }
        }

        context.restoreGState()
    }

    /// The sawtooth marks on the attacker's side of a front — the standard military
    /// map symbol.
    private func drawTeeth(along points: [CGPoint], tint: CGColor, size: CGFloat,
                           context: CGContext) {
        let spacing = 0.06
        var fraction = spacing / 2
        context.setFillColor(tint)
        while fraction < 1 {
            defer { fraction += spacing }
            guard let sample = Geometry.pointAlong(points, fraction: fraction) else { continue }
            let across = CGVector(dx: -sample.direction.dy, dy: sample.direction.dx)
            let tip = CGPoint(x: sample.point.x + across.dx * size,
                              y: sample.point.y + across.dy * size)
            let left = CGPoint(x: sample.point.x - sample.direction.dx * size,
                               y: sample.point.y - sample.direction.dy * size)
            let right = CGPoint(x: sample.point.x + sample.direction.dx * size,
                                y: sample.point.y + sample.direction.dy * size)
            context.beginPath()
            context.move(to: tip)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.fillPath()
        }
    }

    private func drawArrow(at point: CGPoint, direction: CGVector, length: CGFloat,
                           tint: CGColor, width: CGFloat, context: CGContext) {
        let magnitude = max(sqrt(direction.dx * direction.dx + direction.dy * direction.dy), 0.0001)
        let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
        let tip = CGPoint(x: point.x + unit.dx * length, y: point.y + unit.dy * length)
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
        let headLength = length * 0.45
        let headWidth = length * 0.30
        let base = CGPoint(x: tip.x - unit.dx * headLength, y: tip.y - unit.dy * headLength)

        context.saveGState()
        context.setStrokeColor(tint)
        context.setFillColor(tint)
        context.setLineWidth(width)
        context.beginPath()
        context.move(to: point)
        context.addLine(to: base)
        context.strokePath()

        context.beginPath()
        context.move(to: tip)
        context.addLine(to: CGPoint(x: base.x + perpendicular.dx * headWidth,
                                    y: base.y + perpendicular.dy * headWidth))
        context.addLine(to: CGPoint(x: base.x - perpendicular.dx * headWidth,
                                    y: base.y - perpendicular.dy * headWidth))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private func drawCities(snapshot: WorldSnapshot,
                            style: MapRenderStyle,
                            transform: MapTransform,
                            pixel: PixelPass?,
                            context: CGContext) throws {
        let bounds = transform.visibleBounds
        let year = snapshot.date.year
        // Reserve space taken by labels already placed, so names do not pile up.
        var placed: [CGRect] = []
        let fontSize: CGFloat = pixel == nil ? 12 : 6

        for city in try library.cities() {
            guard city.importance <= style.maximumCityImportance else { continue }
            if style.showsCapitalsOnly && !city.isCapital { continue }
            guard bounds.contains(city.coordinate) else { continue }

            let point = transform.point(for: city.coordinate)
            let dotColor = color(city.isCapital ? style.capitalDotHex : style.cityDotHex)
            let radius: CGFloat

            if pixel == nil {
                radius = city.isCapital ? 4 : 3
                context.setFillColor(dotColor)
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2))
                context.setStrokeColor(color(style.labelOutlineHex))
                context.setLineWidth(1)
                context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                 width: radius * 2, height: radius * 2))
            } else {
                // A circle three pixels across is a square with the corners guessed
                // at, so the pixel style draws the square: an ink block with the dot
                // colour set into it.
                radius = city.isCapital ? 2 : 1
                let box = PixelGrid.snap(CGRect(x: point.x - radius, y: point.y - radius,
                                                width: radius * 2, height: radius * 2))
                context.setFillColor(color(style.labelOutlineHex))
                context.fill(box.insetBy(dx: -1, dy: -1))
                context.setFillColor(dotColor)
                context.fill(box)
            }

            let name = city.name(inYear: year)
            let origin = CGPoint(x: point.x + radius + (pixel == nil ? 4 : 2),
                                 y: point.y - fontSize / 2 - 1)
            let size = TextDrawing.measure(name, fontSize: fontSize, weight: 600, usesSerif: false)
            let box = CGRect(origin: origin, size: size).insetBy(dx: -2, dy: -2)
            guard !placed.contains(where: { $0.intersects(box) }) else { continue }
            placed.append(box)

            TextDrawing.draw(name, at: pixel == nil ? origin : PixelGrid.snap(origin),
                             fontSize: fontSize, weight: 600, usesSerif: false,
                             color: color(style.cityLabelHex),
                             outline: color(style.labelOutlineHex),
                             outlineWidth: pixel == nil ? 2 : 1,
                             context: context)
        }
    }

    private func drawCountryLabels(snapshot: WorldSnapshot,
                                   countries: [String: Country],
                                   style: MapRenderStyle,
                                   transform: MapTransform,
                                   pixel: PixelPass?,
                                   context: CGContext) throws {
        // One label per country, anchored at the centre of its largest holding.
        var largestUnit: [String: (id: String, area: Double)] = [:]
        let units = try library.units()
        let byID = Dictionary(units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (unitID, owner) in snapshot.ownership {
            guard let unit = byID[unitID] else { continue }
            if let current = largestUnit[owner], current.area >= unit.area { continue }
            largestUnit[owner] = (unitID, unit.area)
        }

        let bounds = transform.visibleBounds
        var placed: [CGRect] = []

        for (countryID, holding) in largestUnit.sorted(by: { $0.value.area > $1.value.area }) {
            guard let country = countries[countryID],
                  let unit = byID[holding.id],
                  bounds.contains(unit.anchor) else { continue }

            let point = transform.point(for: unit.anchor)
            // Shrink the label for small holdings so it does not spill across borders.
            let fontSize: CGFloat
            let usesShortName: Bool
            if pixel == nil {
                fontSize = holding.area > 200 ? 18 : (holding.area > 40 ? 14 : 11)
                usesShortName = fontSize < 12
            } else {
                // Sizes are in buffer pixels here, so these are the *upscaled* label
                // heights divided by the scale: nine pixels is a 45-point label on a
                // 1080-wide export. Below about six the system font stops resolving
                // into distinguishable letters at all.
                fontSize = holding.area > 200 ? 9 : (holding.area > 40 ? 7 : 6)
                usesShortName = fontSize < 7
            }
            let text = usesShortName ? country.shortName : country.name.uppercased()
            // A serif face and letter spacing are detail the grid cannot hold; at
            // these sizes both just smear the glyphs.
            let usesSerif = pixel == nil
            let spacing: Double = pixel == nil ? 1.5 : 0
            let size = TextDrawing.measure(text, fontSize: fontSize, weight: 700,
                                           usesSerif: usesSerif, letterSpacing: spacing)
            var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            if pixel != nil { origin = PixelGrid.snap(origin) }
            let box = CGRect(origin: origin, size: size).insetBy(dx: -4, dy: -3)
            guard !placed.contains(where: { $0.intersects(box) }) else { continue }
            placed.append(box)

            TextDrawing.draw(text, at: origin, fontSize: fontSize, weight: 700,
                             usesSerif: usesSerif,
                             color: color(style.labelHex),
                             outline: color(style.labelOutlineHex),
                             outlineWidth: pixel == nil ? 3 : 1,
                             letterSpacing: spacing, context: context)
        }
    }

    private func drawArmy(_ army: Army,
                          countries: [String: Country],
                          style: MapRenderStyle,
                          transform: MapTransform,
                          pixel: PixelPass?,
                          context: CGContext) {
        let point = transform.point(for: army.position)
        let tint = colorCache[army.countryID] ?? color(style.neutralLandHex)

        if pixel != nil {
            drawPixelArmy(army, at: point, tint: tint, style: style, context: context)
            return
        }

        // NATO-style counter: a rectangle carrying the owner's colour.
        let box = CGRect(x: point.x - 17, y: point.y - 11, width: 34, height: 22)
        context.saveGState()
        context.setFillColor(tint)
        context.fill(box)
        context.setStrokeColor(color(style.labelOutlineHex))
        context.setLineWidth(1.5)
        context.stroke(box)

        // Strength bar underneath, so weakened formations read at a glance.
        let barWidth = box.width * CGFloat(min(max(army.strength, 0), 1))
        context.setFillColor(CGColor(red: 0.93, green: 0.86, blue: 0.75, alpha: 0.9))
        context.fill(CGRect(x: box.minX, y: box.maxY + 2, width: barWidth, height: 2.5))

        TextDrawing.draw(army.icon.abbreviation,
                         at: CGPoint(x: box.midX - 9, y: box.midY - 6),
                         fontSize: 11, weight: 800, usesSerif: false,
                         color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
                         outline: nil, outlineWidth: 0, context: context)
        context.restoreGState()
    }

    /// A formation in the pixel style: a sprite of what it is, painted in the colour
    /// of whoever owns it, with the strength bar underneath.
    ///
    /// A three-letter code inside a box is unreadable once the box is twelve pixels
    /// wide, which is why this is a sprite rather than the counter scaled down.
    private func drawPixelArmy(_ army: Army,
                               at point: CGPoint,
                               tint: CGColor,
                               style: MapRenderStyle,
                               context: CGContext) {
        let sprite = PixelSprite.army(army.icon)
        let origin = PixelGrid.snap(CGPoint(x: point.x - CGFloat(sprite.width) / 2,
                                            y: point.y - CGFloat(sprite.height) / 2))

        context.saveGState()
        drawSprite(sprite, at: origin, cell: 1, body: tint, style: style, context: context)

        let full = CGFloat(sprite.width) - 2
        let bar = CGRect(x: origin.x + 1, y: origin.y + CGFloat(sprite.height),
                         width: full, height: 1)
        context.setFillColor(color(style.labelOutlineHex))
        context.fill(bar.insetBy(dx: -1, dy: -1))
        context.setFillColor(FlagRenderer.cgColor(PixelPalette.paper))
        context.fill(CGRect(x: bar.minX, y: bar.minY,
                            width: (full * CGFloat(min(max(army.strength, 0), 1))).rounded(),
                            height: bar.height))
        context.restoreGState()
    }

    /// Paints a sprite as one filled rectangle per run of equal tone.
    private func drawSprite(_ sprite: PixelSprite,
                            at origin: CGPoint,
                            cell: CGFloat,
                            body: CGColor,
                            style: MapRenderStyle,
                            context: CGContext) {
        let ink = color(style.labelOutlineHex)
        let light = FlagRenderer.cgColor(PixelPalette.paper)
        let accent = FlagRenderer.cgColor(PixelPalette.danger)

        for run in sprite.runs {
            let fill: CGColor
            switch run.tone {
            case .empty: continue
            case .ink: fill = ink
            case .body: fill = body
            case .light: fill = light
            case .accent: fill = accent
            }
            context.setFillColor(fill)
            context.fill(CGRect(x: origin.x + CGFloat(run.x) * cell,
                                y: origin.y + CGFloat(run.y) * cell,
                                width: CGFloat(run.width) * cell,
                                height: cell))
        }
    }

    private func drawBattle(_ battle: BattleMarker,
                            style: MapRenderStyle,
                            transform: MapTransform,
                            pixel: PixelPass?,
                            context: CGContext) {
        let point = transform.point(for: battle.coordinate)

        if pixel != nil {
            drawPixelBattle(battle, at: point, style: style, context: context)
            return
        }

        let radius: CGFloat = battle.kind.importance == 1 ? 13 : 9

        context.saveGState()
        context.setFillColor(CGColor(red: 0.70, green: 0.26, blue: 0.23, alpha: 0.92))
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2))
        context.setStrokeColor(color(style.labelOutlineHex))
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                         width: radius * 2, height: radius * 2))

        TextDrawing.draw(battle.kind.glyph,
                         at: CGPoint(x: point.x - radius * 0.62, y: point.y - radius * 0.72),
                         fontSize: radius * 1.15, weight: 700, usesSerif: false,
                         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                         outline: nil, outlineWidth: 0, context: context)

        if !battle.title.isEmpty {
            TextDrawing.draw(battle.title,
                             at: CGPoint(x: point.x + radius + 5, y: point.y - 8),
                             fontSize: 13, weight: 700, usesSerif: true,
                             color: color(style.labelHex),
                             outline: color(style.labelOutlineHex), outlineWidth: 3,
                             context: context)
        }
        context.restoreGState()
    }

    /// A battle in the pixel style: crossed swords, an explosion, an anchor — drawn
    /// as sprites, because an emoji rasterised at twelve pixels is a smudge.
    private func drawPixelBattle(_ battle: BattleMarker,
                                 at point: CGPoint,
                                 style: MapRenderStyle,
                                 context: CGContext) {
        let sprite = PixelSprite.battle(battle.kind)
        let origin = PixelGrid.snap(CGPoint(x: point.x - CGFloat(sprite.width) / 2,
                                            y: point.y - CGFloat(sprite.height) / 2))

        context.saveGState()
        drawSprite(sprite, at: origin, cell: 1,
                   body: FlagRenderer.cgColor(PixelPalette.danger), style: style,
                   context: context)

        if !battle.title.isEmpty {
            TextDrawing.draw(battle.title,
                             at: PixelGrid.snap(CGPoint(x: origin.x + CGFloat(sprite.width) + 2,
                                                        y: point.y - 3)),
                             fontSize: 6, weight: 700, usesSerif: false,
                             color: color(style.labelHex),
                             outline: color(style.labelOutlineHex), outlineWidth: 1,
                             context: context)
        }
        context.restoreGState()
    }

    private func drawText(_ text: ResolvedText, viewport: CGSize, pixel: PixelPass?,
                          context: CGContext) {
        guard text.opacity > 0.001, !text.content.isEmpty else { return }

        let centre = CGPoint(
            x: (text.position.x + text.offset.x) * viewport.width,
            y: (text.position.y + text.offset.y) * viewport.height
        )
        var spacing = text.style.letterSpacing + text.extraLetterSpacing
        // Titles are authored in output points. On the low-resolution pass they are
        // divided by the upscale factor, so a 64-point title still fills the same
        // share of the frame — it is simply built from chunky pixels once blown up.
        var fontSize = CGFloat(text.style.fontSize) * CGFloat(text.scale)
        if let pixel {
            fontSize = pixel.size(fontSize, minimum: 5)
            spacing = (spacing / Double(pixel.scale)).rounded()
        }
        let size = TextDrawing.measure(text.content, fontSize: fontSize,
                                       weight: text.style.weight,
                                       usesSerif: text.style.usesSerif,
                                       letterSpacing: spacing)

        var origin: CGPoint
        switch text.style.alignment {
        case .center: origin = CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        case .leading: origin = CGPoint(x: centre.x, y: centre.y - size.height / 2)
        case .trailing: origin = CGPoint(x: centre.x - size.width, y: centre.y - size.height / 2)
        }
        if pixel != nil { origin = PixelGrid.snap(origin) }

        context.saveGState()
        context.setAlpha(CGFloat(text.opacity * text.style.opacity))
        // A blurred drop shadow is a gradient by another name: on the pixel pass it
        // would ring every letter with colours the palette does not have.
        if text.style.shadowRadius > 0, pixel == nil {
            context.setShadow(offset: CGSize(width: 0, height: 2),
                              blur: CGFloat(text.style.shadowRadius),
                              color: CGColor(red: 0, green: 0, blue: 0,
                                             alpha: CGFloat(text.style.shadowOpacity)))
        }
        TextDrawing.draw(text.content, at: origin, fontSize: fontSize,
                         weight: text.style.weight, usesSerif: text.style.usesSerif,
                         color: color(text.style.colorHex),
                         outline: text.style.outlineColorHex.map { color($0) },
                         outlineWidth: CGFloat(text.style.outlineWidth),
                         letterSpacing: spacing,
                         context: context)
        context.restoreGState()
    }
}

/// What the low-resolution pass needs to know about itself.
///
/// Carried through the draw methods instead of a bare `Bool` so that a layer can ask
/// how big something authored in output points should be in buffer pixels, rather
/// than each one hard-coding its own guess at the scale.
private struct PixelPass {
    /// How many output pixels one buffer pixel becomes.
    let scale: CGFloat

    /// Converts a size authored in output points into buffer pixels.
    func size(_ points: CGFloat, minimum: CGFloat = 1) -> CGFloat {
        max(minimum, (points / scale).rounded())
    }
}

extension ArmyIcon {
    /// Two-letter code drawn inside the unit counter.
    public var abbreviation: String {
        switch self {
        case .infantry: return "INF"
        case .armour: return "ARM"
        case .cavalry: return "CAV"
        case .airborne: return "ABN"
        case .marine: return "MAR"
        case .artillery: return "ART"
        case .fleet: return "FLT"
        case .airForce: return "AIR"
        case .partisan: return "PAR"
        }
    }
}
