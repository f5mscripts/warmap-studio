import CoreGraphics
import XCTest
@testable import WarMapStudio

/// The pixel-art render path.
///
/// The parts that can be checked without eyes are checked here: that the buffer
/// maths produces whole-number scaling, that geometry lands on the grid, that
/// colours collapse onto the palette, and — end to end — that a rendered frame is
/// actually made of square blocks rather than merely looking chunky in a preview.
final class PixelStyleTests: XCTestCase {

    // MARK: - Buffer

    func testBufferScalesByAWholeNumber() {
        let buffer = PixelGrid.buffer(for: CGSize(width: 1080, height: 1920), shortEdge: 200)
        XCTAssertEqual(buffer?.scale, 5)
        XCTAssertEqual(buffer?.size, CGSize(width: 216, height: 384))
    }

    func testBufferNeverLeavesTheViewportUncovered() {
        for size in [CGSize(width: 1080, height: 1920),
                     CGSize(width: 1920, height: 1080),
                     CGSize(width: 393, height: 759),
                     CGSize(width: 1000, height: 1000),
                     CGSize(width: 137, height: 291)] {
            guard let buffer = PixelGrid.buffer(for: size, shortEdge: 200) else {
                return XCTFail("no buffer for \(size)")
            }
            XCTAssertEqual(buffer.scale, buffer.scale.rounded(), "scale must be whole")
            XCTAssertGreaterThanOrEqual(buffer.outputSize.width, size.width)
            XCTAssertGreaterThanOrEqual(buffer.outputSize.height, size.height)
        }
    }

    func testBufferRefusesADegenerateViewport() {
        XCTAssertNil(PixelGrid.buffer(for: .zero, shortEdge: 200))
        XCTAssertNil(PixelGrid.buffer(for: CGSize(width: 400, height: 0), shortEdge: 200))
    }

    // MARK: - Snapping

    func testSnappingPutsEveryPointOnTheGrid() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10.4, y: 20.6))
        path.addLine(to: CGPoint(x: 30.5, y: 41.2))
        path.addLine(to: CGPoint(x: 12.9, y: 8.1))
        path.closeSubpath()

        var points: [CGPoint] = []
        PixelGrid.snap(path).applyWithBlock { element in
            if element.pointee.type != .closeSubpath {
                points.append(element.pointee.points[0])
            }
        }

        XCTAssertEqual(points.count, 3)
        for point in points {
            XCTAssertEqual(point.x, point.x.rounded())
            XCTAssertEqual(point.y, point.y.rounded())
        }
    }

    func testSnappingLeavesFarOffGeometryAlone() {
        // Rounding coordinates this large buys nothing and risks precision, so they
        // are passed through untouched.
        XCTAssertEqual(PixelGrid.snap(CGFloat(2e7) + 0.5), CGFloat(2e7) + 0.5)
        XCTAssertEqual(PixelGrid.snap(CGFloat.infinity), CGFloat.infinity)
    }

    func testOddStrokeWidthsAreOffsetHalfAPixel() {
        XCTAssertEqual(PixelGrid.lineOffset(forWidth: 1), 0.5)
        XCTAssertEqual(PixelGrid.lineOffset(forWidth: 3), 0.5)
        XCTAssertEqual(PixelGrid.lineOffset(forWidth: 2), 0)
        XCTAssertEqual(PixelGrid.lineOffset(forWidth: 4), 0)
    }

    func testSnappedRectangleNeverCollapses() {
        let thin = PixelGrid.snap(CGRect(x: 4.2, y: 9.1, width: 0.3, height: 0.2))
        XCTAssertGreaterThanOrEqual(thin.width, 1)
        XCTAssertGreaterThanOrEqual(thin.height, 1)
    }

    // MARK: - Palette

    func testQuantisingAlwaysLandsOnThePalette() {
        for hex in ["FF0000", "123456", "7C838C", "000000", "FFFFFF", "8A9378"] {
            XCTAssertTrue(PixelPalette.all.contains(PixelPalette.nearest(to: hex)),
                          "\(hex) quantised off the palette")
        }
    }

    func testQuantisingKeepsHue() {
        XCTAssertEqual(PixelPalette.nearest(to: "FF0000"), "C22E2E")
        XCTAssertEqual(PixelPalette.nearest(to: "00FF00"), "1FA850")
        XCTAssertEqual(PixelPalette.nearest(to: "0B0F1A"), PixelPalette.ink)
        XCTAssertEqual(PixelPalette.nearest(to: "FFFFFF"), PixelPalette.paper)
    }

    func testCountriesNeverTakeATerrainColour() {
        // A country coloured like the sea must not be quantised into the sea.
        let assigned = PixelPalette.factionColors(for: ["atlantis": PixelPalette.sea,
                                                        "arctica": PixelPalette.deepSea,
                                                        "greyland": PixelPalette.neutralLand])
        for (id, hex) in assigned {
            XCTAssertTrue(PixelPalette.faction.contains(hex), "\(id) took a reserved colour")
        }
    }

    func testSimilarCountriesAreSpreadAcrossThePalette() {
        // Three reds a few percent apart: at 200 pixels across they would otherwise
        // be the same side.
        let assigned = PixelPalette.factionColors(for: ["a": "C42F2F",
                                                        "b": "C63131",
                                                        "c": "C83333"])
        XCTAssertEqual(Set(assigned.values).count, 3)
    }

    func testCountriesShareOnlyOnceThePaletteRunsOut() {
        var cast: [String: String] = [:]
        for index in 0..<(PixelPalette.faction.count + 4) {
            cast["country-\(index)"] = "C42F2F"
        }
        let assigned = PixelPalette.factionColors(for: cast)
        XCTAssertEqual(assigned.count, cast.count)
        XCTAssertEqual(Set(assigned.values).count, PixelPalette.faction.count)
    }

    func testQuantisationIsDeterministic() {
        let colors = ["france": "56749E", "germany": "5E6860", "italy": "808A54",
                      "uk": "7A6094", "ussr": "962C2C"]
        XCTAssertEqual(PixelPalette.factionColors(for: colors),
                       PixelPalette.factionColors(for: colors),
                       "the same cast must always get the same colours")
    }

    // MARK: - Sprites

    func testEveryUnitAndBattleHasArt() {
        for icon in ArmyIcon.allCases {
            let sprite = PixelSprite.army(icon)
            XCTAssertEqual(sprite.width, 12, "\(icon) is not on the 12-pixel grid")
            XCTAssertEqual(sprite.height, 12, "\(icon) is not on the 12-pixel grid")
            XCTAssertFalse(sprite.runs.isEmpty, "\(icon) has no visible pixels")
            XCTAssertTrue(sprite.runs.contains { $0.tone == .body },
                          "\(icon) carries none of its owner's colour")
        }
        for kind in BattleKind.allCases {
            let sprite = PixelSprite.battle(kind)
            XCTAssertEqual(sprite.width, 12, "\(kind) is not on the 12-pixel grid")
            XCTAssertEqual(sprite.height, 12, "\(kind) is not on the 12-pixel grid")
            XCTAssertFalse(sprite.runs.isEmpty, "\(kind) has no visible pixels")
        }
    }

    func testRunsReproduceTheArt() {
        let sprite = PixelSprite(["..kk", "kbbk", "...."])
        let runs = sprite.runs
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0], PixelSprite.Run(x: 2, y: 0, width: 2, tone: .ink))
        XCTAssertEqual(runs[1], PixelSprite.Run(x: 0, y: 1, width: 1, tone: .ink))
        XCTAssertEqual(runs[2], PixelSprite.Run(x: 1, y: 1, width: 2, tone: .body))
        XCTAssertNil(runs.first { $0.tone == .empty })
    }

    // MARK: - Style

    func testPixelPresetIsAPixelStyle() {
        let style = MapRenderStyle.preset(.pixel)
        XCTAssertTrue(style.isPixelated)
        XCTAssertGreaterThan(style.pixelShortEdge, 100)
        // Anything translucent would blend two palette entries into a third.
        XCTAssertEqual(style.territoryOpacity, 1)
        XCTAssertFalse(style.showsGraticule)
        for hex in [style.oceanHex, style.oceanDeepHex, style.neutralLandHex,
                    style.borderHex, style.coastlineHex, style.labelHex,
                    style.labelOutlineHex, style.capitalDotHex] {
            XCTAssertTrue(PixelPalette.all.contains(hex), "\(hex) is not a palette entry")
        }
    }

    @MainActor
    func testTheDefaultStyleSettingCanPickPixel() throws {
        let suite = "PixelStyleTests.defaults"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(AppState(defaults: defaults).preferredMapStyle,
                     "with no preference stored, the era still chooses")

        let state = AppState(defaults: defaults)
        state.defaultMapStyle = MapStyle.pixel.rawValue
        XCTAssertEqual(AppState(defaults: defaults).preferredMapStyle, .pixel,
                       "a chosen default must survive into the next launch")
    }

    func testOtherStylesAreUntouched() {
        for style in MapStyle.allCases where style != .pixel {
            XCTAssertFalse(MapRenderStyle.preset(style).isPixelated,
                           "\(style) should not have become pixelated")
        }
    }

    func testStyleSavedBeforeThePixelFieldsStillDecodes() throws {
        // Exactly the shape a project written by an earlier build carries.
        let json = """
        {"oceanHex":"121C26","oceanDeepHex":"0C141C","neutralLandHex":"686C74",
         "coastlineHex":"3C4652","borderHex":"0E1014","coastlineWidth":1,"borderWidth":2,
         "cityDotHex":"F2EDE1","cityLabelHex":"F2EDE1","capitalDotHex":"C9A227",
         "labelHex":"F2EDE1","labelOutlineHex":"0B0D10","territoryOpacity":1,
         "contestedHighlight":0.16,"showsCities":true,"maximumCityImportance":2,
         "showsCapitalsOnly":false,"showsCountryLabels":true,"showsFlags":false,
         "showsGraticule":false,"graticuleHex":"1E2A36"}
        """
        let style = try JSONDecoder().decode(MapRenderStyle.self, from: Data(json.utf8))
        XCTAssertFalse(style.isPixelated)
        XCTAssertEqual(style.pixelShortEdge, MapRenderStyle().pixelShortEdge)
        XCTAssertEqual(style.oceanHex, "121C26")
    }

    func testStyleSurvivesARoundTrip() throws {
        let original = MapRenderStyle.preset(.pixel)
        let decoded = try JSONDecoder().decode(MapRenderStyle.self,
                                               from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Rendering

    /// The point of the whole style: the output must be made of square blocks, and
    /// of very few colours. Both are measured from the pixels themselves.
    func testPixelRenderProducesSquareBlocksOfPaletteColour() throws {
        let side = 400
        let bitmap = try render(style: pixelStyleWithoutText(), side: side)
        let scale = 2  // 400 / 200

        // Scanned first and asserted once: a per-pixel XCTAssert over 160,000 pixels
        // costs more than the render it is checking.
        var brokenBlock: String?
        scan: for y in stride(from: 0, to: side, by: scale) {
            for x in stride(from: 0, to: side, by: scale) {
                let reference = bitmap.color(x: x, y: y)
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let column = x + dx
                        let row = y + dy
                        guard column < side, row < side else { continue }
                        if bitmap.color(x: column, y: row) != reference {
                            brokenBlock = "pixel (\(column), \(row)) differs from the block at (\(x), \(y))"
                            break scan
                        }
                    }
                }
            }
        }
        XCTAssertNil(brokenBlock, brokenBlock ?? "")

        // Territory fills, sea and ink only — no anti-aliased in-between shades.
        XCTAssertLessThanOrEqual(bitmap.distinctColors.count, PixelPalette.all.count,
                                 "more colours than the palette holds")
    }

    func testTheOrdinaryStyleIsNotPixelated() throws {
        let bitmap = try render(style: .preset(.military), side: 400)
        // The gradient sea alone puts this far past the palette's 24 entries.
        XCTAssertGreaterThan(bitmap.distinctColors.count, PixelPalette.all.count)
    }

    // MARK: - Helpers

    /// The pixel style with labels off, so the assertions measure the render path
    /// rather than however the system font happens to rasterise this year.
    private func pixelStyleWithoutText() -> MapRenderStyle {
        var style = MapRenderStyle.preset(.pixel)
        style.showsCountryLabels = false
        style.showsCities = false
        return style
    }

    private func render(style: MapRenderStyle, side: Int) throws -> Bitmap {
        let project = ScenarioLibrary.ww2Europe()
        let snapshot = WorldSnapshot(time: 0,
                                     date: project.timeline.historicalRange.start,
                                     ownership: project.timeline.initialOwnership,
                                     camera: MapCamera(center: GeoCoordinate(longitude: 15,
                                                                             latitude: 50),
                                                       span: 60))
        let bitmap = try Bitmap(side: side)
        let renderer = MapSceneRenderer(library: MapLibrary(bundle: .main))
        try renderer.render(snapshot,
                            transform: MapTransform(projection: .mercator,
                                                    camera: snapshot.camera,
                                                    viewport: CGSize(width: side, height: side)),
                            style: style,
                            countries: project.countryIndex,
                            into: bitmap.context)
        return bitmap
    }

    /// A square BGRA canvas whose pixels can be read back.
    private struct Bitmap {
        let context: CGContext
        let side: Int

        init(side: Int) throws {
            self.side = side
            guard let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                throw WarMapError.renderFailed(detail: "the test canvas could not be created")
            }
            self.context = context
        }

        func color(x: Int, y: Int) -> UInt32 {
            guard let data = context.data else { return 0 }
            let row = context.bytesPerRow
            return data.load(fromByteOffset: y * row + x * 4, as: UInt32.self)
        }

        var distinctColors: Set<UInt32> {
            var colors: Set<UInt32> = []
            for y in 0..<side {
                for x in 0..<side {
                    colors.insert(color(x: x, y: y))
                }
            }
            return colors
        }
    }
}
