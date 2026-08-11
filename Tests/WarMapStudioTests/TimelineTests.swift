import CoreGraphics
import XCTest
@testable import WarMapStudio

final class TimelineTests: XCTestCase {

    private let range = HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                           end: HistoricalDate(year: 1945, month: 5, day: 8))

    private func makeTimeline(items: [TimelineItem] = [],
                              ownership: [String: String] = ["POL": "poland", "DEU": "germany"])
    -> Timeline {
        Timeline(duration: 30,
                 historicalRange: range,
                 items: items,
                 initialOwnership: ownership,
                 initialCamera: MapCamera(center: GeoCoordinate(longitude: 15, latitude: 52),
                                          span: 40))
    }

    // MARK: - Time mapping

    func testTimeMapsLinearlyOntoTheHistoricalRange() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.date(at: 0), range.start)
        XCTAssertEqual(timeline.date(at: 30), range.end)
        XCTAssertEqual(timeline.date(at: 15).days(since: range.start),
                       range.dayCount / 2, accuracy: 1)
    }

    func testDateToTimeIsTheInverseOfTimeToDate() {
        let timeline = makeTimeline()
        for t in stride(from: 0.0, through: 30.0, by: 3.0) {
            XCTAssertEqual(timeline.time(for: timeline.date(at: t)), t, accuracy: 0.05)
        }
    }

    func testDateIsMonotonicAcrossTheWholeVideo() {
        let timeline = makeTimeline()
        var previous = timeline.date(at: 0)
        for t in stride(from: 0.0, through: 30.0, by: 0.25) {
            let current = timeline.date(at: t)
            XCTAssertGreaterThanOrEqual(current, previous, "the date counter went backwards at \(t)s")
            previous = current
        }
    }

    // MARK: - Territory capture

    private func invasionTimeline() -> Timeline {
        makeTimeline(items: [
            TimelineItem(title: "Invasion of Poland",
                         start: 4,
                         duration: 6,
                         easing: .linear,
                         action: .captureTerritory(units: ["POL"],
                                                   attacker: "germany",
                                                   bearing: 90))
        ])
    }

    func testTerritoryIsUncontestedBeforeTheInvasionStarts() {
        let snapshot = TimelineEvaluator(timeline: invasionTimeline()).snapshot(at: 2)
        XCTAssertEqual(snapshot.ownership["POL"], "poland")
        XCTAssertTrue(snapshot.contested.isEmpty)
    }

    func testTerritoryIsContestedMidSweepAndStillHeldByTheDefender() throws {
        let snapshot = TimelineEvaluator(timeline: invasionTimeline()).snapshot(at: 7)
        XCTAssertEqual(snapshot.ownership["POL"], "poland",
                       "ownership must not flip until the sweep completes")
        let contested = try XCTUnwrap(snapshot.contested["POL"])
        XCTAssertEqual(contested.attackerID, "germany")
        XCTAssertEqual(contested.defenderID, "poland")
        XCTAssertEqual(contested.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(contested.bearing, 90)
    }

    func testTerritoryTransfersOnceTheSweepFinishes() {
        let evaluator = TimelineEvaluator(timeline: invasionTimeline())
        let snapshot = evaluator.snapshot(at: 10)
        XCTAssertEqual(snapshot.ownership["POL"], "germany")
        XCTAssertTrue(snapshot.contested.isEmpty, "a finished capture is no longer contested")
    }

    func testCaptureProgressIsMonotonic() {
        let evaluator = TimelineEvaluator(timeline: invasionTimeline())
        var previous = 0.0
        for t in stride(from: 4.0, through: 10.0, by: 0.25) {
            let progress = evaluator.snapshot(at: t).contested["POL"]?.progress ?? 1.0
            XCTAssertGreaterThanOrEqual(progress, previous - 0.0001,
                                        "sweep went backwards at \(t)s")
            previous = progress
        }
    }

    func testInstantTransferNeedsNoSweep() {
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Annexation", start: 5, duration: 0,
                         action: .transferTerritory(units: ["POL"], to: "germany"))
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)
        XCTAssertEqual(evaluator.snapshot(at: 4).ownership["POL"], "poland")
        XCTAssertEqual(evaluator.snapshot(at: 6).ownership["POL"], "germany")
        XCTAssertTrue(evaluator.snapshot(at: 6).contested.isEmpty)
    }

    // MARK: - Determinism

    /// Scrubbing must land on exactly the frame playback would have produced —
    /// otherwise the exported video and the preview drift apart.
    func testScrubbingBackwardsMatchesPlayingForwards() {
        let evaluator = TimelineEvaluator(timeline: invasionTimeline())
        let times = stride(from: 0.0, through: 20.0, by: 0.5).map { $0 }

        let forwards = times.map { evaluator.snapshot(at: $0) }
        let backwards = times.reversed().map { evaluator.snapshot(at: $0) }.reversed()

        for (a, b) in zip(forwards, Array(backwards)) {
            XCTAssertEqual(a.ownership, b.ownership)
            XCTAssertEqual(a.contested["POL"]?.progress, b.contested["POL"]?.progress)
            XCTAssertEqual(a.camera, b.camera)
            XCTAssertEqual(a.date, b.date)
        }
    }

    func testEvaluationDoesNotDependOnItemOrderInTheArray() {
        let a = TimelineItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                             title: "A", start: 2, duration: 4,
                             action: .captureTerritory(units: ["POL"], attacker: "germany",
                                                       bearing: 90))
        let b = TimelineItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                             title: "B", start: 8, duration: 4,
                             action: .captureTerritory(units: ["DEU"], attacker: "ussr",
                                                       bearing: 270))

        let forwards = TimelineEvaluator(timeline: makeTimeline(items: [a, b]))
        let reversed = TimelineEvaluator(timeline: makeTimeline(items: [b, a]))

        for t in stride(from: 0.0, through: 16.0, by: 0.5) {
            XCTAssertEqual(forwards.snapshot(at: t).ownership,
                           reversed.snapshot(at: t).ownership,
                           "array order changed the result at \(t)s")
        }
    }

    func testDisabledItemsAreIgnored() {
        var item = TimelineItem(title: "Invasion", start: 4, duration: 2,
                                action: .captureTerritory(units: ["POL"], attacker: "germany",
                                                          bearing: 90))
        item.isEnabled = false
        let snapshot = TimelineEvaluator(timeline: makeTimeline(items: [item])).snapshot(at: 10)
        XCTAssertEqual(snapshot.ownership["POL"], "poland")
    }

    // MARK: - Camera

    func testCameraKeyframesInterpolateAndChain() {
        let first = MapCamera(center: GeoCoordinate(longitude: 19, latitude: 52), span: 12)
        let second = MapCamera(center: GeoCoordinate(longitude: 37, latitude: 55), span: 8)
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Zoom to Poland", start: 0, duration: 4, easing: .linear,
                         action: .cameraMove(to: first)),
            TimelineItem(title: "Move to Moscow", start: 6, duration: 4, easing: .linear,
                         action: .cameraMove(to: second)),
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)

        XCTAssertEqual(evaluator.snapshot(at: 4).camera, first)
        // Between the two moves the camera holds the first keyframe.
        XCTAssertEqual(evaluator.snapshot(at: 5).camera, first)
        XCTAssertEqual(evaluator.snapshot(at: 10).camera, second)

        let mid = evaluator.snapshot(at: 8).camera
        XCTAssertGreaterThan(mid.center.longitude, first.center.longitude)
        XCTAssertLessThan(mid.center.longitude, second.center.longitude)
    }

    // MARK: - Armies

    func testArmyMovesAndArrivesExactly() throws {
        let start = GeoCoordinate(longitude: 13, latitude: 52)
        let destination = GeoCoordinate(longitude: 21, latitude: 52)
        let army = Army(name: "German 6th Army", countryID: "germany",
                        size: 250_000, position: start, icon: .armour)

        var timeline = makeTimeline(items: [
            TimelineItem(title: "Advance", start: 2, duration: 4, easing: .linear,
                         action: .moveArmy(armyID: army.id, to: destination))
        ])
        timeline.initialArmies = [army]
        let evaluator = TimelineEvaluator(timeline: timeline)

        XCTAssertEqual(evaluator.snapshot(at: 0).armies.first?.position.longitude, 13)
        let mid = try XCTUnwrap(evaluator.snapshot(at: 4).armies.first)
        XCTAssertEqual(mid.position.longitude, 17, accuracy: 0.01)
        XCTAssertEqual(evaluator.snapshot(at: 6).armies.first?.position.longitude, 21)
    }

    func testArmySpawnAndRemoval() {
        let army = Army(name: "Reserve", countryID: "ussr", size: 100_000,
                        position: GeoCoordinate(longitude: 37, latitude: 55))
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Mobilise", start: 3, duration: 0,
                         action: .spawnArmy(army)),
            TimelineItem(title: "Destroyed", start: 12, duration: 0,
                         action: .removeArmy(armyID: army.id)),
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)
        XCTAssertTrue(evaluator.snapshot(at: 1).armies.isEmpty)
        XCTAssertEqual(evaluator.snapshot(at: 5).armies.count, 1)
        XCTAssertTrue(evaluator.snapshot(at: 15).armies.isEmpty)
    }

    // MARK: - Text and the date counter

    func testDateCounterTakesItsContentFromTheTimelineClock() throws {
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Date", start: 0, duration: 30, easing: .linear,
                         action: .showText(.dateCounter(format: .dayMonthNameYear)))
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)

        let atStart = try XCTUnwrap(evaluator.snapshot(at: 0.5).texts.first)
        XCTAssertTrue(atStart.content.contains("1939"), "got \(atStart.content)")

        let atEnd = try XCTUnwrap(evaluator.snapshot(at: 29).texts.first)
        XCTAssertTrue(atEnd.content.contains("1945"), "got \(atEnd.content)")
    }

    func testTypewriterRevealsCharactersOverTime() throws {
        let element = TextElement(content: "GERMANY INVADES POLAND",
                                  style: .title, animation: .typewriter)
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Headline", start: 0, duration: 4, easing: .linear,
                         action: .showText(element))
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)
        let early = try XCTUnwrap(evaluator.snapshot(at: 0.2).texts.first).content
        let late = try XCTUnwrap(evaluator.snapshot(at: 1.2).texts.first).content
        XCTAssertLessThan(early.count, late.count)
        XCTAssertTrue("GERMANY INVADES POLAND".hasPrefix(late))
    }

    func testTextDisappearsAfterItsClipEnds() {
        let timeline = makeTimeline(items: [
            TimelineItem(title: "Title", start: 1, duration: 3,
                         action: .showText(TextElement(content: "SEPTEMBER 1, 1939")))
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)
        XCTAssertFalse(evaluator.snapshot(at: 2).texts.isEmpty)
        XCTAssertTrue(evaluator.snapshot(at: 8).texts.isEmpty)
    }

    // MARK: - Frontlines

    func testFrontlineMorphsBetweenShapes() throws {
        let initial = [GeoCoordinate(longitude: 20, latitude: 54),
                       GeoCoordinate(longitude: 20, latitude: 50)]
        let advanced = [GeoCoordinate(longitude: 26, latitude: 54),
                        GeoCoordinate(longitude: 26, latitude: 50)]
        let front = Frontline(points: initial, attackerID: "germany", defenderID: "ussr")

        let timeline = makeTimeline(items: [
            TimelineItem(title: "Front appears", start: 0, duration: 0,
                         action: .showFrontline(front)),
            TimelineItem(title: "Advance", start: 2, duration: 4, easing: .linear,
                         action: .moveFrontline(frontlineID: front.id, to: advanced)),
        ])
        let evaluator = TimelineEvaluator(timeline: timeline)

        XCTAssertEqual(evaluator.snapshot(at: 1).frontlines.count, 1)
        let mid = try XCTUnwrap(evaluator.snapshot(at: 4).frontlines.first)
        let midLongitude = try XCTUnwrap(mid.points.first?.longitude)
        XCTAssertEqual(midLongitude, 23, accuracy: 0.2)

        let end = try XCTUnwrap(evaluator.snapshot(at: 7).frontlines.first)
        XCTAssertEqual(end.points.first?.longitude ?? 0, 26, accuracy: 0.001)
    }

    // MARK: - Frames

    func testFrameTimesMatchTheRequestedFrameRate() {
        let evaluator = TimelineEvaluator(timeline: makeTimeline())
        XCTAssertEqual(evaluator.frameTimes(fps: 30).count, 900)
        XCTAssertEqual(evaluator.frameTimes(fps: 60).count, 1800)
        XCTAssertEqual(evaluator.frameTimes(fps: 30).first, 0)
    }

    func testSnapshotClampsOutsideTheVideo() {
        let evaluator = TimelineEvaluator(timeline: invasionTimeline())
        XCTAssertEqual(evaluator.snapshot(at: -5).time, 0)
        XCTAssertEqual(evaluator.snapshot(at: 999).time, 30)
    }

    // MARK: - Easing

    func testEasingCurvesStartAtZeroAndEndAtOne() {
        for curve in EasingCurve.allCases {
            XCTAssertEqual(curve.apply(0), 0, accuracy: 0.001, "\(curve) should start at 0")
            XCTAssertEqual(curve.apply(1), 1, accuracy: 0.001, "\(curve) should end at 1")
        }
    }

    func testEasingClampsOutOfRangeInput() {
        for curve in EasingCurve.allCases {
            XCTAssertEqual(curve.apply(-3), 0, accuracy: 0.001)
            XCTAssertEqual(curve.apply(4), 1, accuracy: 0.001)
        }
    }

    func testPolylineInterpolationHandlesDifferentVertexCounts() {
        let coarse = [GeoCoordinate(longitude: 0, latitude: 0),
                      GeoCoordinate(longitude: 10, latitude: 0)]
        let fine = (0...20).map { GeoCoordinate(longitude: Double($0) / 2, latitude: 5) }
        let blended = Interpolate.polyline(coarse, fine, 0.5)
        XCTAssertEqual(blended.count, 64)
        XCTAssertEqual(blended.first?.latitude ?? -1, 2.5, accuracy: 0.001)
    }

    func testColourInterpolation() {
        XCTAssertEqual(Interpolate.colorHex("000000", "FFFFFF", 0), "000000")
        XCTAssertEqual(Interpolate.colorHex("000000", "FFFFFF", 1), "FFFFFF")
        XCTAssertEqual(Interpolate.colorHex("000000", "FFFFFF", 0.5), "808080")
    }
}
