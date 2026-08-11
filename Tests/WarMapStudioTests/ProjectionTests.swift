import CoreGraphics
import XCTest
@testable import WarMapStudio

final class ProjectionTests: XCTestCase {

    // MARK: - Projections

    func testMercatorRoundTripsAcrossTheUsableRange() {
        for lon in stride(from: -180.0, through: 180.0, by: 30) {
            for lat in stride(from: -80.0, through: 80.0, by: 20) {
                let original = GeoCoordinate(longitude: lon, latitude: lat)
                let result = MapProjectionKind.mercator.unproject(
                    MapProjectionKind.mercator.project(original)
                )
                XCTAssertEqual(result.longitude, lon, accuracy: 1e-9)
                XCTAssertEqual(result.latitude, lat, accuracy: 1e-9)
            }
        }
    }

    func testEquirectangularRoundTrips() {
        let original = GeoCoordinate(longitude: 21.0, latitude: 52.2)
        let result = MapProjectionKind.equirectangular.unproject(
            MapProjectionKind.equirectangular.project(original)
        )
        XCTAssertEqual(result.longitude, 21.0, accuracy: 1e-9)
        XCTAssertEqual(result.latitude, 52.2, accuracy: 1e-9)
    }

    func testMercatorClampsBeyondItsLatitudeLimit() {
        let north = MapProjectionKind.mercator.project(GeoCoordinate(longitude: 0, latitude: 89.9))
        XCTAssertTrue(north.y.isFinite, "Mercator must not diverge at the pole")
        XCTAssertEqual(north.y, 180, accuracy: 0.1,
                       "the cut-off latitude should project to a square map")
    }

    func testMercatorEquatorIsTheOrigin() {
        let p = MapProjectionKind.mercator.project(GeoCoordinate(longitude: 0, latitude: 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-12)
        XCTAssertEqual(p.y, 0, accuracy: 1e-12)
    }

    func testMercatorPreservesLatitudeOrdering() {
        let south = MapProjectionKind.mercator.project(GeoCoordinate(longitude: 0, latitude: 10))
        let north = MapProjectionKind.mercator.project(GeoCoordinate(longitude: 0, latitude: 60))
        XCTAssertLessThan(south.y, north.y, "projected y must increase northwards")
    }

    // MARK: - Camera

    func testCameraFittingCoversTheRequestedBounds() {
        let bounds = GeoBounds(minLongitude: -12, minLatitude: 35, maxLongitude: 42, maxLatitude: 68)
        let viewport = CGSize(width: 1080, height: 1920)
        let camera = MapCamera.fitting(bounds, in: viewport)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)
        let visible = transform.visibleBounds

        XCTAssertLessThanOrEqual(visible.minLongitude, bounds.minLongitude)
        XCTAssertGreaterThanOrEqual(visible.maxLongitude, bounds.maxLongitude)
        XCTAssertLessThanOrEqual(visible.minLatitude, bounds.minLatitude)
        XCTAssertGreaterThanOrEqual(visible.maxLatitude, bounds.maxLatitude)
    }

    func testCameraClampsExtremeSpans() {
        XCTAssertEqual(MapCamera(center: .init(longitude: 0, latitude: 0), span: 1e9).span,
                       MapCamera.maximumSpan)
        XCTAssertEqual(MapCamera(center: .init(longitude: 0, latitude: 0), span: 0).span,
                       MapCamera.minimumSpan)
    }

    func testCameraInterpolationHitsBothEnds() {
        let a = MapCamera(center: GeoCoordinate(longitude: 0, latitude: 50), span: 60)
        let b = MapCamera(center: GeoCoordinate(longitude: 37, latitude: 55), span: 8)

        let start = MapCamera.interpolate(a, b, 0)
        XCTAssertEqual(start.span, a.span, accuracy: 1e-9)
        XCTAssertEqual(start.center.longitude, a.center.longitude, accuracy: 1e-9)

        let end = MapCamera.interpolate(a, b, 1)
        XCTAssertEqual(end.span, b.span, accuracy: 1e-9)
        XCTAssertEqual(end.center.longitude, b.center.longitude, accuracy: 1e-9)
    }

    func testCameraZoomInterpolationIsGeometric() {
        // Halfway through a 100x zoom should be 10x in, not 50x — otherwise the
        // move spends its whole second crawling at the end.
        let a = MapCamera(center: GeoCoordinate(longitude: 0, latitude: 0), span: 100)
        let b = MapCamera(center: GeoCoordinate(longitude: 0, latitude: 0), span: 1)
        XCTAssertEqual(MapCamera.interpolate(a, b, 0.5).span, 10, accuracy: 1e-6)
    }

    func testCameraInterpolationTakesShortWayAcrossTheAntimeridian() {
        let a = MapCamera(center: GeoCoordinate(longitude: 170, latitude: 0), span: 40)
        let b = MapCamera(center: GeoCoordinate(longitude: -170, latitude: 0), span: 40)
        let mid = MapCamera.interpolate(a, b, 0.5)
        // Going the short way passes through 180, not back through 0.
        XCTAssertEqual(abs(mid.center.longitude), 180, accuracy: 1e-6)
    }

    // MARK: - Transform

    func testTransformPutsCameraCentreAtViewportCentre() {
        let viewport = CGSize(width: 1080, height: 1920)
        let camera = MapCamera(center: GeoCoordinate(longitude: 21, latitude: 52), span: 40)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)
        let point = transform.point(for: camera.center)
        XCTAssertEqual(point.x, viewport.width / 2, accuracy: 0.001)
        XCTAssertEqual(point.y, viewport.height / 2, accuracy: 0.001)
    }

    func testTransformRoundTripsScreenPoints() {
        let viewport = CGSize(width: 800, height: 600)
        let camera = MapCamera(center: GeoCoordinate(longitude: 10, latitude: 45), span: 30)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)

        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 600), CGPoint(x: 137, y: 429)] {
            let back = transform.point(for: transform.coordinate(for: point))
            XCTAssertEqual(back.x, point.x, accuracy: 0.001)
            XCTAssertEqual(back.y, point.y, accuracy: 0.001)
        }
    }

    func testTransformRoundTripsUnderRotation() {
        let viewport = CGSize(width: 800, height: 600)
        let camera = MapCamera(center: GeoCoordinate(longitude: 10, latitude: 45),
                               span: 30, rotation: 0.4)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)
        let point = CGPoint(x: 210, y: 380)
        let back = transform.point(for: transform.coordinate(for: point))
        XCTAssertEqual(back.x, point.x, accuracy: 0.001)
        XCTAssertEqual(back.y, point.y, accuracy: 0.001)
    }

    func testNorthIsUpOnScreen() {
        let viewport = CGSize(width: 800, height: 600)
        let camera = MapCamera(center: GeoCoordinate(longitude: 0, latitude: 50), span: 30)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)
        let north = transform.point(for: GeoCoordinate(longitude: 0, latitude: 55))
        let south = transform.point(for: GeoCoordinate(longitude: 0, latitude: 45))
        XCTAssertLessThan(north.y, south.y, "screen y must grow southwards")
    }

    /// The affine transform is what lets cached paths survive panning, so it has to
    /// agree with the per-point path exactly.
    func testAffineTransformMatchesPerPointProjection() {
        let viewport = CGSize(width: 1080, height: 1920)
        let camera = MapCamera(center: GeoCoordinate(longitude: 21, latitude: 52),
                               span: 40, rotation: 0.25)
        let transform = MapTransform(projection: .mercator, camera: camera, viewport: viewport)
        let affine = transform.projectedToScreen

        for coordinate in [
            GeoCoordinate(longitude: 0, latitude: 0),
            GeoCoordinate(longitude: 37, latitude: 55),
            GeoCoordinate(longitude: -9, latitude: 38),
            GeoCoordinate(longitude: 140, latitude: -30),
        ] {
            let projected = MapProjectionKind.mercator.project(coordinate)
            let viaAffine = CGPoint(x: projected.x, y: projected.y).applying(affine)
            let direct = transform.point(for: coordinate)
            XCTAssertEqual(viaAffine.x, direct.x, accuracy: 0.001)
            XCTAssertEqual(viaAffine.y, direct.y, accuracy: 0.001)
        }
    }

    func testLevelOfDetailTracksZoom() {
        XCTAssertEqual(LevelOfDetail.forUnitsPerPoint(1.0), .coarse)
        XCTAssertEqual(LevelOfDetail.forUnitsPerPoint(0.2), .medium)
        XCTAssertEqual(LevelOfDetail.forUnitsPerPoint(0.01), .full)
    }

    // MARK: - Bounds

    func testBoundsExpansionAndIntersection() {
        var box = GeoBounds.empty
        box.expand(toInclude: GeoCoordinate(longitude: 10, latitude: 20))
        box.expand(toInclude: GeoCoordinate(longitude: -5, latitude: 40))
        XCTAssertEqual(box.minLongitude, -5)
        XCTAssertEqual(box.maxLatitude, 40)
        XCTAssertTrue(box.contains(GeoCoordinate(longitude: 0, latitude: 30)))
        XCTAssertTrue(box.intersects(GeoBounds(minLongitude: 0, minLatitude: 0,
                                               maxLongitude: 100, maxLatitude: 100)))
        XCTAssertFalse(box.intersects(GeoBounds(minLongitude: 100, minLatitude: 0,
                                                maxLongitude: 120, maxLatitude: 10)))
    }
}
