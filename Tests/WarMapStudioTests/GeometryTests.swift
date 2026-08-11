import CoreGraphics
import XCTest
@testable import WarMapStudio

/// The half-plane clip is the primitive every border animation runs through, so it
/// gets tested hard: if it is wrong, every invasion in every export is wrong.
final class GeometryTests: XCTestCase {

    private let unitSquare = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100),
    ]

    // MARK: - Half-plane clipping

    func testClipKeepingEverythingReturnsOriginalArea() {
        let result = Geometry.clip(unitSquare,
                                   origin: CGPoint(x: -50, y: 0),
                                   normal: CGVector(dx: 1, dy: 0))
        XCTAssertEqual(abs(Geometry.signedArea(result)), 10_000, accuracy: 0.001)
    }

    func testClipKeepingNothingReturnsEmpty() {
        let result = Geometry.clip(unitSquare,
                                   origin: CGPoint(x: 150, y: 0),
                                   normal: CGVector(dx: 1, dy: 0))
        XCTAssertTrue(result.isEmpty)
    }

    func testClipAtMidpointHalvesTheArea() {
        let result = Geometry.clip(unitSquare,
                                   origin: CGPoint(x: 50, y: 0),
                                   normal: CGVector(dx: 1, dy: 0))
        XCTAssertEqual(abs(Geometry.signedArea(result)), 5_000, accuracy: 0.001)
    }

    func testClipOnDiagonalHalvesTheArea() {
        // A cut through the centre at 45° should still take exactly half.
        let result = Geometry.clip(unitSquare,
                                   origin: CGPoint(x: 50, y: 50),
                                   normal: CGVector(dx: 0.7071, dy: 0.7071))
        XCTAssertEqual(abs(Geometry.signedArea(result)), 5_000, accuracy: 1.0)
    }

    func testClipProducesPointsOnTheKeptSideOnly() {
        let result = Geometry.clip(unitSquare,
                                   origin: CGPoint(x: 40, y: 0),
                                   normal: CGVector(dx: 1, dy: 0))
        for p in result {
            XCTAssertGreaterThanOrEqual(p.x, 40 - 0.0001,
                                        "clip kept a point on the discarded side")
        }
    }

    // MARK: - Sweep

    func testSweepAtZeroCapturesNothing() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let (origin, normal) = Geometry.sweepHalfPlane(bounds: bounds,
                                                       direction: CGVector(dx: 1, dy: 0),
                                                       progress: 0)
        let result = Geometry.clip(unitSquare, origin: origin, normal: normal)
        XCTAssertEqual(abs(Geometry.signedArea(result)), 0, accuracy: 0.001)
    }

    func testSweepAtOneCapturesEverything() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let (origin, normal) = Geometry.sweepHalfPlane(bounds: bounds,
                                                       direction: CGVector(dx: 1, dy: 0),
                                                       progress: 1)
        let result = Geometry.clip(unitSquare, origin: origin, normal: normal)
        XCTAssertEqual(abs(Geometry.signedArea(result)), 10_000, accuracy: 0.001)
    }

    func testSweepProgressIncreasesCapturedAreaMonotonically() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        var previous: CGFloat = -1
        for step in 0...10 {
            let progress = Double(step) / 10
            let (origin, normal) = Geometry.sweepHalfPlane(bounds: bounds,
                                                           direction: CGVector(dx: 1, dy: 0),
                                                           progress: progress)
            let area = abs(Geometry.signedArea(Geometry.clip(unitSquare, origin: origin, normal: normal)))
            XCTAssertGreaterThanOrEqual(area, previous,
                                        "captured area went backwards at progress \(progress)")
            previous = area
        }
    }

    func testSweepWorksInAnyDirection() {
        // A north-east advance across the same square must still finish complete.
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let (origin, normal) = Geometry.sweepHalfPlane(bounds: bounds,
                                                       direction: CGVector(dx: -0.6, dy: -0.8),
                                                       progress: 1)
        let result = Geometry.clip(unitSquare, origin: origin, normal: normal)
        XCTAssertEqual(abs(Geometry.signedArea(result)), 10_000, accuracy: 0.001)
    }

    // MARK: - Hit testing

    func testContainsDetectsInteriorAndExteriorPoints() {
        XCTAssertTrue(Geometry.contains(unitSquare, point: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(Geometry.contains(unitSquare, point: CGPoint(x: 150, y: 50)))
        XCTAssertFalse(Geometry.contains(unitSquare, point: CGPoint(x: -1, y: 50)))
    }

    func testContainsHandlesConcaveShapes() {
        // An L: the notch must read as outside.
        let shape = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 40),
            CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 100), CGPoint(x: 0, y: 100),
        ]
        XCTAssertTrue(Geometry.contains(shape, point: CGPoint(x: 20, y: 20)))
        XCTAssertFalse(Geometry.contains(shape, point: CGPoint(x: 70, y: 70)))
    }

    // MARK: - Polylines

    func testSimplifyRemovesCollinearPoints() {
        let line = (0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let simplified = Geometry.simplify(line, tolerance: 0.5)
        XCTAssertEqual(simplified.count, 2)
    }

    func testSimplifyKeepsSignificantDetail() {
        let line = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 60),
            CGPoint(x: 100, y: 0),
        ]
        XCTAssertEqual(Geometry.simplify(line, tolerance: 1).count, 3)
    }

    func testSimplifyPreservesEndpoints() {
        let line = (0...20).map { CGPoint(x: CGFloat($0), y: CGFloat($0 % 3)) }
        let simplified = Geometry.simplify(line, tolerance: 5)
        XCTAssertEqual(simplified.first, line.first)
        XCTAssertEqual(simplified.last, line.last)
    }

    func testSmoothAddsPointsAndStaysWithinTheHull() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)]
        let smoothed = Geometry.smooth(line, iterations: 2)
        XCTAssertGreaterThan(smoothed.count, line.count)
        for p in smoothed {
            XCTAssertGreaterThanOrEqual(p.x, -0.001)
            XCTAssertLessThanOrEqual(p.x, 100.001)
            XCTAssertLessThanOrEqual(p.y, 100.001)
        }
    }

    func testSmoothKeepsOpenLineEndpoints() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)]
        let smoothed = Geometry.smooth(line, iterations: 3)
        XCTAssertEqual(smoothed.first, line.first)
        XCTAssertEqual(smoothed.last, line.last)
    }

    func testLengthOfKnownPolyline() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), CGPoint(x: 3, y: 14)]
        XCTAssertEqual(Geometry.length(line), 15, accuracy: 0.0001)
    }

    func testPointAlongFindsTheMidpoint() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = Geometry.pointAlong(line, fraction: 0.5)
        XCTAssertEqual(result?.point.x ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(result?.direction.dx ?? 0, 1, accuracy: 0.0001)
    }

    func testPointAlongClampsOutOfRangeFractions() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        XCTAssertEqual(Geometry.pointAlong(line, fraction: -5)?.point.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(Geometry.pointAlong(line, fraction: 5)?.point.x ?? -1, 100, accuracy: 0.0001)
    }

    func testCentroidOfSquareIsItsCentre() {
        let c = Geometry.centroid(unitSquare)
        XCTAssertEqual(c.x, 50, accuracy: 0.0001)
        XCTAssertEqual(c.y, 50, accuracy: 0.0001)
    }
}
