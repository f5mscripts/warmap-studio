import XCTest
@testable import WarMapStudio

final class ProjectTests: XCTestCase {

    private func makeProject() -> WarMapProject {
        ScenarioLibrary.ww2Europe()
    }

    // MARK: - Serialization

    func testProjectSurvivesACodableRoundTrip() throws {
        let original = makeProject()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WarMapProject.self,
                                         from: try encoder.encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.era, original.era)
        XCTAssertEqual(decoded.timeline.items.count, original.timeline.items.count)
        XCTAssertEqual(decoded.timeline.initialOwnership, original.timeline.initialOwnership)
        XCTAssertEqual(decoded.countries.count, original.countries.count)
        XCTAssertEqual(decoded.timeline.historicalRange, original.timeline.historicalRange)
    }

    /// A round trip must preserve what the video actually looks like, not merely
    /// decode without throwing.
    func testRoundTripProducesIdenticalFrames() throws {
        let original = makeProject()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WarMapProject.self,
                                         from: try encoder.encode(original))

        let before = TimelineEvaluator(timeline: original.timeline)
        let after = TimelineEvaluator(timeline: decoded.timeline)

        for time in stride(from: 0.0, through: original.timeline.duration, by: 1.5) {
            let a = before.snapshot(at: time)
            let b = after.snapshot(at: time)
            XCTAssertEqual(a.ownership, b.ownership, "ownership differs at \(time)s")
            XCTAssertEqual(a.date, b.date, "date differs at \(time)s")
            XCTAssertEqual(a.camera, b.camera, "camera differs at \(time)s")
            XCTAssertEqual(a.texts.map(\.content), b.texts.map(\.content),
                           "text differs at \(time)s")
        }
    }

    func testFutureFormatVersionIsRejectedWithAClearError() throws {
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder.iso8601.encode(makeProject())
        ) as! [String: Any]
        json["formatVersion"] = WarMapProject.currentFormatVersion + 5
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try JSONDecoder.iso8601.decode(WarMapProject.self, from: data)) { error in
            guard case WarMapError.projectVersionUnsupported = error else {
                return XCTFail("expected a version error, got \(error)")
            }
        }
    }

    func testMissingOptionalFieldsFallBackRatherThanFailing() throws {
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder.iso8601.encode(makeProject())
        ) as! [String: Any]
        for key in ["subtitle", "wars", "audioClips", "branches", "mapStyle", "dateFormat"] {
            json.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder.iso8601.decode(WarMapProject.self, from: data)
        XCTAssertEqual(decoded.subtitle, "")
        XCTAssertTrue(decoded.wars.isEmpty)
        XCTAssertEqual(decoded.mapStyle, .military)
    }

    // MARK: - Store

    func testSaveLoadAndDeleteRoundTripOnDisk() throws {
        let store = ProjectStore()
        let project = makeProject()
        let package = try store.save(project)

        addTeardownBlock { try? FileManager.default.removeItem(at: package) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
        let loaded = try store.load(from: package)
        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.timeline.items.count, project.timeline.items.count)

        let summaries = store.listProjects()
        XCTAssertTrue(summaries.contains { $0.id == project.id })

        if let summary = summaries.first(where: { $0.id == project.id }) {
            try store.delete(summary)
            XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
        }
    }

    func testDuplicateGetsANewIdentityAndName() throws {
        let store = ProjectStore()
        let project = makeProject()
        let package = try store.save(project)
        addTeardownBlock { try? FileManager.default.removeItem(at: package) }

        let summary = try XCTUnwrap(store.listProjects().first { $0.id == project.id })
        let copy = try store.duplicate(summary)
        addTeardownBlock { try? FileManager.default.removeItem(at: store.packageURL(for: copy)) }

        XCTAssertNotEqual(copy.id, project.id)
        XCTAssertNotEqual(copy.name, project.name)
        XCTAssertEqual(copy.timeline.items.count, project.timeline.items.count)
    }

    func testLoadingAMissingProjectReportsCorruption() {
        let store = ProjectStore()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope.warmap")
        XCTAssertThrowsError(try store.load(from: missing)) { error in
            guard case WarMapError.projectCorrupt = error else {
                return XCTFail("expected a corruption error, got \(error)")
            }
        }
    }

    func testUnsupportedAudioIsRejectedBeforeImport() {
        XCTAssertThrowsError(
            try AudioClip.validate(url: URL(fileURLWithPath: "/tmp/track.flac"))
        ) { error in
            guard case WarMapError.unsupportedAudioFormat = error else {
                return XCTFail("expected an audio format error, got \(error)")
            }
        }
        XCTAssertNoThrow(try AudioClip.validate(url: URL(fileURLWithPath: "/tmp/track.m4a")))
        XCTAssertNoThrow(try AudioClip.validate(url: URL(fileURLWithPath: "/tmp/track.MP3")))
    }

    // MARK: - Branching

    func testBranchingCopiesTheTimelineAndLeavesTheOriginalAlone() {
        var project = makeProject()
        let originalCount = project.timeline.items.count
        let divergence = HistoricalDate(year: 1941, month: 6, day: 22)

        let branch = project.branch(named: "France survives", at: divergence)
        project.activeBranchID = branch.id

        XCTAssertEqual(project.timeline.items.count, originalCount,
                       "the original timeline must not be touched")
        XCTAssertLessThan(project.activeTimeline.items.count, originalCount,
                          "a branch drops everything after the divergence")
        XCTAssertEqual(project.activeBranchName, "France survives")

        // Editing the branch still leaves the original intact.
        project.activeTimeline.add(TimelineItem(title: "What if", start: 20, duration: 1,
                                                action: .transferTerritory(units: ["DEU"],
                                                                           to: "france")))
        XCTAssertEqual(project.timeline.items.count, originalCount)
    }

    func testSwitchingBackToTheOriginalRestoresIt() {
        var project = makeProject()
        let originalCount = project.timeline.items.count
        let branch = project.branch(named: "Alternate", at: HistoricalDate(year: 1942))
        project.activeBranchID = branch.id
        project.activeBranchID = nil
        XCTAssertEqual(project.activeTimeline.items.count, originalCount)
        XCTAssertEqual(project.activeBranchName, "Original Timeline")
    }

    // MARK: - Export configuration

    func testBuiltInPresetsHaveTheAdvertisedShape() {
        XCTAssertEqual(ExportPreset.tiktok.width, 1080)
        XCTAssertEqual(ExportPreset.tiktok.height, 1920)
        XCTAssertTrue(ExportPreset.tiktok.isPortrait)
        XCTAssertEqual(ExportPreset.youtube.aspectRatio, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(ExportPreset.square.aspectRatio, 1.0, accuracy: 0.001)
    }

    func testCustomPresetForcesEvenDimensionsAndSaneLimits() {
        // H.264 rejects odd dimensions; a stray pixel column shows up green.
        let odd = ExportPreset.custom(width: 1081, height: 1921, fps: 30)
        XCTAssertEqual(odd.width % 2, 0)
        XCTAssertEqual(odd.height % 2, 0)

        let absurd = ExportPreset.custom(width: 99_999, height: 1, fps: 500)
        XCTAssertLessThanOrEqual(absurd.width, 4096)
        XCTAssertGreaterThanOrEqual(absurd.height, 64)
        XCTAssertLessThanOrEqual(absurd.fps, 60)
    }

    func testFrameCountMatchesDurationAndRate() {
        let timeline = makeProject().timeline
        let evaluator = TimelineEvaluator(timeline: timeline)
        XCTAssertEqual(evaluator.frameTimes(fps: 30).count,
                       Int((timeline.duration * 30).rounded()))
    }

    func testSizeEstimateGrowsWithResolutionAndDuration() {
        let short = ExportPreset.tiktok.estimatedBytes(duration: 10)
        let long = ExportPreset.tiktok.estimatedBytes(duration: 60)
        XCTAssertGreaterThan(long, short)
        XCTAssertGreaterThan(ExportPreset.youtube.estimatedBytes(duration: 30),
                             ExportPreset.square.estimatedBytes(duration: 30))
    }

    // MARK: - The shipped scenarios

    func testEveryPresetScenarioBuildsAndPlays() throws {
        for preset in ScenarioLibrary.all {
            let project = preset.build()
            XCTAssertFalse(project.name.isEmpty, "\(preset.id) has no name")
            XCTAssertFalse(project.countries.isEmpty, "\(preset.id) has no countries")
            XCTAssertFalse(project.timeline.items.isEmpty, "\(preset.id) has no clips")
            XCTAssertGreaterThan(project.timeline.duration, 0)

            // Every clip must fall inside the video.
            for item in project.timeline.items {
                XCTAssertGreaterThanOrEqual(item.start, -0.001,
                                            "\(preset.id): \(item.title) starts before zero")
                XCTAssertLessThanOrEqual(item.start, project.timeline.duration + 0.001,
                                         "\(preset.id): \(item.title) starts after the end")
            }

            // And it must evaluate at both ends without falling over.
            let evaluator = TimelineEvaluator(timeline: project.timeline)
            XCTAssertFalse(evaluator.snapshot(at: 0).ownership.isEmpty,
                           "\(preset.id) starts with nobody owning anything")
            _ = evaluator.snapshot(at: project.timeline.duration)
        }
    }

    func testScenarioOwnershipReferencesRealTerritoriesAndCountries() throws {
        let units = Set(try MapLibrary(bundle: .main).units().map(\.id))
        for preset in ScenarioLibrary.all {
            let project = preset.build()
            let known = Set(project.countries.map(\.id))
            for (unit, owner) in project.timeline.initialOwnership {
                XCTAssertTrue(units.contains(unit),
                              "\(preset.id) assigns unknown territory \(unit)")
                XCTAssertTrue(known.contains(owner),
                              "\(preset.id) assigns \(unit) to unknown country \(owner)")
            }
        }
    }

    /// The demo is the first thing anyone sees, so its content is asserted directly.
    func testTheDemoActuallyChangesHandsWhenPlayed() {
        let project = ScenarioLibrary.ww2Europe()
        let evaluator = TimelineEvaluator(timeline: project.timeline)

        let opening = evaluator.snapshot(at: 0)
        XCTAssertEqual(opening.ownership["POL"], "poland")
        XCTAssertEqual(opening.ownership["DEU"], "germany")
        XCTAssertEqual(opening.ownership["UKR-W"], "poland",
                       "interwar Poland should reach east of today's border")

        let end = evaluator.snapshot(at: project.timeline.duration)
        XCTAssertEqual(end.ownership["DEU"], "ussr", "Berlin should have fallen by the end")
        XCTAssertNotEqual(end.ownership["POL"], "poland",
                          "Poland changes hands during the war")

        // Something should be mid-sweep during the invasion of Poland.
        let invasion = evaluator.snapshot(at: project.timeline.time(
            for: HistoricalDate(year: 1939, month: 9, day: 14)))
        XCTAssertFalse(invasion.contested.isEmpty,
                       "the invasion should be visibly in progress in mid-September 1939")
    }

    func testTheDemoSpawnsAndDestroysTheSameArmy() {
        let project = ScenarioLibrary.ww2Europe()
        let evaluator = TimelineEvaluator(timeline: project.timeline)
        let duringBarbarossa = project.timeline.time(for: HistoricalDate(year: 1942, month: 1, day: 1))
        let afterStalingrad = project.timeline.time(for: HistoricalDate(year: 1943, month: 6, day: 1))

        XCTAssertEqual(evaluator.snapshot(at: duringBarbarossa).armies.count, 1,
                       "the 6th Army should be on the map in 1942")
        XCTAssertTrue(evaluator.snapshot(at: afterStalingrad).armies.isEmpty,
                      "the removal must reference the same army that was spawned")
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension ProjectTests {

    /// Every clip must finish inside the video. A capture that is still sweeping
    /// when the last frame is written never actually happens — which is how the
    /// demo's fall of Berlin was silently unfinished.
    func testEveryScenarioClipCompletesBeforeTheVideoEnds() {
        for preset in ScenarioLibrary.all {
            let timeline = preset.build().timeline
            for item in timeline.items {
                XCTAssertLessThanOrEqual(
                    item.end, timeline.duration + 0.001,
                    "\(preset.id): “\(item.title)” ends at \(item.end)s, past the \(timeline.duration)s video"
                )
            }
        }
    }
}
