import CoreGraphics
import XCTest
@testable import WarMapStudio

/// The presentation layer: how bold the map reads, the pre-war card, the camera
/// drift, and the pacing of text.
final class PresentationTests: XCTestCase {

    // MARK: - Bolder map

    func testSaturationBoostPushesColoursAwayFromGrey() {
        // A muted field grey should come out more colourful, not just brighter.
        let boosted = ColorTuning.saturated("5E6860", by: 0.5)
        guard let before = PixelPalette.components("5E6860"),
              let after = PixelPalette.components(boosted) else {
            return XCTFail("unparseable colour")
        }

        let spreadBefore = max(before.r, before.g, before.b) - min(before.r, before.g, before.b)
        let spreadAfter = max(after.r, after.g, after.b) - min(after.r, after.g, after.b)
        XCTAssertGreaterThan(spreadAfter, spreadBefore, "the colour should get more saturated")
    }

    func testSaturationBoostLeavesGreyAndZeroAmountAlone() {
        // Grey has no hue to push away from, so it must survive untouched.
        XCTAssertEqual(ColorTuning.saturated("808080", by: 0.8), "808080")
        XCTAssertEqual(ColorTuning.saturated("5E6860", by: 0), "5E6860")
        XCTAssertEqual(ColorTuning.saturated("not-a-colour", by: 0.5), "not-a-colour")
    }

    func testSaturationBoostStaysInRange() {
        for hex in ["FF0000", "0B0D10", "F2EDE1", "1FA850"] {
            let boosted = ColorTuning.saturated(hex, by: 1)
            let rgb = PixelPalette.components(boosted)
            XCTAssertNotNil(rgb, "\(hex) boosted into something unparseable: \(boosted)")
            for channel in [rgb?.r, rgb?.g, rgb?.b].compactMap({ $0 }) {
                XCTAssertGreaterThanOrEqual(channel, 0)
                XCTAssertLessThanOrEqual(channel, 255)
            }
        }
    }

    func testTheBolderStylesActuallyGotBolder() {
        let military = MapRenderStyle.preset(.military)
        XCTAssertGreaterThan(military.contestedHighlight, 0.3,
                             "the advancing edge was too faint to read")
        XCTAssertGreaterThan(military.contestedEdgeWidth, 2)
        XCTAssertGreaterThan(military.borderWidth, 2)
        XCTAssertGreaterThan(military.fillSaturationBoost, 0)
        XCTAssertTrue(military.showsFlags, "flags beside country labels are the point")

        // The pixel style is already at full saturation and must not be pushed.
        XCTAssertEqual(MapRenderStyle.preset(.pixel).fillSaturationBoost, 0)
    }

    // MARK: - Versus card

    private func makeCard() -> VersusCard {
        VersusCard(sideAName: "Allies", sideBName: "Axis",
                   sideACountryIDs: ["uk", "france"],
                   sideBCountryIDs: ["germany"],
                   sideAStrength: 8, sideBStrength: 4)
    }

    func testCardBarsAreRelativeToTheStrongerSide() {
        let fractions = makeCard().barFractions
        XCTAssertEqual(fractions.a, 1, accuracy: 0.001, "the stronger side fills its bar")
        XCTAssertEqual(fractions.b, 0.5, accuracy: 0.001)

        // Two empty sides must not divide by zero.
        let empty = VersusCard(sideAName: "A", sideBName: "B",
                               sideAStrength: 0, sideBStrength: 0)
        XCTAssertEqual(empty.barFractions.a, 0)
        XCTAssertEqual(empty.barFractions.b, 0)
    }

    private func cardTimeline() -> Timeline {
        var timeline = Timeline(duration: 20,
                                historicalRange: HistoricalInterval(
                                    start: HistoricalDate(year: 1939, month: 9, day: 1),
                                    end: HistoricalDate(year: 1945, month: 5, day: 8)))
        timeline.items = [
            TimelineItem(title: "Versus", start: 1, duration: 2,
                         action: .showVersusCard(makeCard()))
        ]
        return timeline
    }

    func testTheCardIsOnScreenOnlyForItsOwnClip() {
        let evaluator = TimelineEvaluator(timeline: cardTimeline())
        XCTAssertNil(evaluator.snapshot(at: 0.5).versusCard, "before the clip")
        XCTAssertNotNil(evaluator.snapshot(at: 2).versusCard, "during the clip")
        XCTAssertNil(evaluator.snapshot(at: 5).versusCard, "after the clip")
    }

    func testTheCardFadesInAndOutRatherThanSnapping() {
        let evaluator = TimelineEvaluator(timeline: cardTimeline())
        let entering = evaluator.snapshot(at: 1.05).versusCard?.opacity ?? 0
        let held = evaluator.snapshot(at: 2).versusCard?.opacity ?? 0
        let leaving = evaluator.snapshot(at: 2.95).versusCard?.opacity ?? 0

        XCTAssertGreaterThan(held, entering)
        XCTAssertGreaterThan(held, leaving)
        XCTAssertEqual(held, 1, accuracy: 0.001, "it should be fully solid in the middle")
        XCTAssertGreaterThanOrEqual(entering, 0)
    }

    func testTheCardSurvivesSaving() throws {
        let item = TimelineItem(title: "Versus", start: 0, duration: 2,
                                action: .showVersusCard(makeCard()))
        let decoded = try JSONDecoder().decode(TimelineItem.self,
                                               from: try JSONEncoder().encode(item))
        guard case .showVersusCard(let card) = decoded.action else {
            return XCTFail("the action decoded as something else")
        }
        XCTAssertEqual(card.sideAName, "Allies")
        XCTAssertEqual(card.sideBCountryIDs, ["germany"])
        XCTAssertEqual(decoded.action.track, .text)
    }

    // MARK: - Camera drift

    private func driftTimeline() -> Timeline {
        Timeline(duration: 30,
                 historicalRange: HistoricalInterval(start: HistoricalDate(year: 1939),
                                                     end: HistoricalDate(year: 1945)),
                 initialCamera: MapCamera(center: GeoCoordinate(longitude: 15, latitude: 50),
                                          span: 60))
    }

    func testTheCameraDriftsInWhileNothingElseMovesIt() {
        let timeline = driftTimeline()
        let still = TimelineEvaluator(timeline: timeline, ambientZoomRate: 0)
        let drifting = TimelineEvaluator(timeline: timeline, ambientZoomRate: 0.02)

        XCTAssertEqual(still.snapshot(at: 10).camera.span,
                       timeline.initialCamera.span, accuracy: 0.0001,
                       "zero rate must leave the camera exactly where it was")

        let start = drifting.snapshot(at: 0).camera.span
        let later = drifting.snapshot(at: 10).camera.span
        XCTAssertEqual(start, timeline.initialCamera.span, accuracy: 0.0001)
        XCTAssertLessThan(later, start, "a held shot should creep closer")
        // Twenty percent per ten seconds at this rate: noticeable, not seasickness.
        XCTAssertGreaterThan(later, start * 0.5)
    }

    func testAKeyframeResetsTheDriftRatherThanFightingIt() {
        var timeline = driftTimeline()
        let target = MapCamera(center: GeoCoordinate(longitude: 20, latitude: 52), span: 30)
        timeline.items = [
            TimelineItem(title: "Move in", start: 5, duration: 2, action: .cameraMove(to: target))
        ]
        let evaluator = TimelineEvaluator(timeline: timeline, ambientZoomRate: 0.02)

        // Straight after the move the camera is where the keyframe put it, with no
        // accumulated drift from the five seconds before it.
        XCTAssertEqual(evaluator.snapshot(at: 7).camera.span, target.span, accuracy: 0.01)
        // And then it starts creeping again from there.
        XCTAssertLessThan(evaluator.snapshot(at: 12).camera.span, target.span)
    }

    func testDriftIsPureAndSurvivesScrubbingBackwards() {
        let evaluator = TimelineEvaluator(timeline: driftTimeline(), ambientZoomRate: 0.02)
        let forwards = (0...10).map { evaluator.snapshot(at: Double($0)).camera.span }
        let backwards = (0...10).reversed().map { evaluator.snapshot(at: Double($0)).camera.span }
        XCTAssertEqual(forwards, backwards.reversed())
    }

    func testANewProjectDriftsByDefaultAndTheSettingSurvivesSaving() throws {
        let project = ScenarioLibrary.ww2Europe()
        XCTAssertGreaterThan(project.ambientZoomRate, 0,
                             "a still camera is the thing this was added to fix")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WarMapProject.self, from: try encoder.encode(project))
        XCTAssertEqual(decoded.ambientZoomRate, project.ambientZoomRate)
    }

    // MARK: - Pacing

    func testTitlesAreBigEnoughToReadOnAPhone() {
        XCTAssertGreaterThanOrEqual(TextStyle.title.fontSize, 80)
        XCTAssertGreaterThan(TextStyle.title.fontSize, TextStyle.subtitle.fontSize)
        XCTAssertGreaterThan(TextStyle.subtitle.fontSize, TextStyle.caption.fontSize)
        // Over a busy map, an outline is what keeps a title legible.
        XCTAssertNotNil(TextStyle.title.outlineColorHex)
        XCTAssertGreaterThan(TextStyle.title.outlineWidth, 0)
    }

    func testTextArrivesQuicklyAndHoldsForMostOfItsLife() {
        let element = TextElement(content: "OPERATION BARBAROSSA", style: .title)
        let date = HistoricalDate(year: 1941, month: 6, day: 22)

        func opacity(at progress: Double) -> Double {
            TextAnimator.resolve(element, progress: progress, date: date,
                                 easing: .easeOut).opacity
        }

        // A fifth of the way in, a caption should already be fully readable rather
        // than still sliding into place.
        XCTAssertEqual(opacity(at: 0.2), 1, accuracy: 0.001)
        XCTAssertEqual(opacity(at: 0.5), 1, accuracy: 0.001)
        XCTAssertLessThan(opacity(at: 0.0), 1)
        XCTAssertLessThan(opacity(at: 1.0), 1, "and it should still fade out at the end")
    }
}
