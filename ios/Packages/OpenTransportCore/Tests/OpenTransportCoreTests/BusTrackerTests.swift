import XCTest
@testable import OpenTransportCore

final class BusTrackerTests: XCTestCase {
    // A straight 1.1 km line going north.
    private let start = LonLat(lon: -0.3763, lat: 39.4699)
    private let end = LonLat(lon: -0.3763, lat: 39.4799)

    private func transit() -> TransitData {
        let direction = RouteDirection(shapes: [[start, end]], stops: ["1", "2"])
        let stops = [
            Stop(id: 1, name: "A", lines: ["7"], lat: start.lat, lon: start.lon),
            Stop(id: 2, name: "B", lines: ["7"], lat: end.lat, lon: end.lon),
        ]
        return TransitData(stops: stops, stopsById: ["1": stops[0], "2": stops[1]],
                           routes: ["7": BusRoute(ida: direction, vuelta: direction)])
    }

    private func fix(number: Int = 1, lat: Double, lon: Double = -0.3763, ts: String) -> BusFix {
        BusFix(number: number, line: "7", destination: "B", lastStop: 1, nextStop: 2,
               lon: lon, lat: lat, timestamp: ts, direction: "ida")
    }

    func testSnapsNewBusToRoute() {
        let tracker = BusTracker(transit: transit())
        // ~20 m east of the line.
        tracker.merge([fix(lat: 39.4749, lon: -0.37607, ts: "2026-10-23T12:00:00")])
        XCTAssertEqual(tracker.buses.count, 1)
        let bus = tracker.buses[0]
        XCTAssertNotNil(bus.route)
        XCTAssertEqual(bus.render.lon, -0.3763, accuracy: 1e-6)
        XCTAssertEqual(bus.render.lat, 39.4749, accuracy: 1e-4)
    }

    func testFarFromRouteIsNotSnapped() {
        let tracker = BusTracker(transit: transit())
        tracker.merge([fix(lat: 39.4749, lon: -0.36, ts: "2026-10-23T12:00:00")])
        XCTAssertNil(tracker.buses[0].route)
        XCTAssertEqual(tracker.buses[0].render.lon, -0.36, accuracy: 1e-9)
    }

    func testEstimatesSpeedAndAdvances() {
        let tracker = BusTracker(transit: transit())
        let t0 = Date(timeIntervalSince1970: 1_000)
        tracker.merge([fix(lat: 39.4709, ts: "2026-10-23T12:00:00")], now: t0)
        // 10 s later, ~111 m further.
        tracker.merge([fix(lat: 39.4719, ts: "2026-10-23T12:00:10")], now: t0.addingTimeInterval(10))
        let bus = tracker.buses[0]
        XCTAssertEqual(bus.speedMps, 11.13 / 2, accuracy: 0.5) // averaged with the initial 0
        let before = bus.routeS
        for frame in 1...60 { tracker.advance(now: t0.addingTimeInterval(10 + Double(frame) / 30)) }
        XCTAssertGreaterThan(bus.routeS, before)
        XCTAssertEqual(bus.bearing, 0, accuracy: 1) // heading north
    }

    func testDropsBusesThatDisappear() {
        let tracker = BusTracker(transit: transit())
        tracker.merge([fix(number: 1, lat: 39.4709, ts: "a"), fix(number: 2, lat: 39.4719, ts: "a")])
        XCTAssertEqual(tracker.buses.count, 2)
        tracker.merge([fix(number: 2, lat: 39.4719, ts: "a")])
        XCTAssertEqual(tracker.buses.map(\.number), [2])
    }

    func testSecondsBetween() {
        XCTAssertEqual(BusTracker.secondsBetween("2026-10-23T12:00:00", "2026-10-23T12:00:15"), 15)
        XCTAssertEqual(BusTracker.secondsBetween("bad", "2026-10-23T12:00:15"), 0)
    }

    func testRouteBounds() {
        let bounds = transit().routes["7"]!.bounds!
        XCTAssertEqual(bounds.south, start.lat)
        XCTAssertEqual(bounds.north, end.lat)
    }
}
