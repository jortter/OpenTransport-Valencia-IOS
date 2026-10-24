import XCTest
@testable import OpenTransportCore

/// Plans between many real stop pairs (offline: straight-line walks, no live
/// waits) so a crash in the planner shows up here rather than on a device.
final class PlannerStressTests: XCTestCase {
    func testPlansAcrossRealNetwork() async throws {
        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("app/src/main/assets")
        let data = try TransitDataLoader.load(from: assets)
        let planner = JourneyPlanner(
            transit: data,
            streetWalk: { a, b in
                let d = TransitMotion.distanceMeters(a, b) * 1.25
                return (d, d / 1.25)
            },
            nextBus: { _, _ in nil }
        )
        let stops = data.stops
        var planned = 0, found = 0
        let step = max(1, stops.count / 25)
        for i in stride(from: 0, to: stops.count, by: step) {
            for j in stride(from: step / 2, to: stops.count, by: step * 3) where i != j {
                let a = stops[i], b = stops[j]
                let options = await planner.plan(from: LonLat(lon: a.lon, lat: a.lat), to: LonLat(lon: b.lon, lat: b.lat))
                planned += 1
                if !options.isEmpty { found += 1 }
                XCTAssertLessThanOrEqual(options.count, 4)
            }
        }
        // Most pairs across the city have a direct or one-transfer bus.
        XCTAssertGreaterThan(Double(found) / Double(planned), 0.5, "\(found)/\(planned) pairs with options")
    }
}
