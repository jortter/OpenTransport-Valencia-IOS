import XCTest
@testable import OpenTransportCore

final class JourneyPlannerTests: XCTestCase {
    // A at the origin; line 1 goes A → B → C; line 2 goes B → D; D is at the destination.
    private let stops = [
        Stop(id: 1, name: "A", lines: ["1"], lat: 39.4700, lon: -0.3800),
        Stop(id: 2, name: "B", lines: ["1", "2"], lat: 39.4750, lon: -0.3800),
        Stop(id: 3, name: "C", lines: ["1"], lat: 39.4800, lon: -0.3800),
        Stop(id: 4, name: "D", lines: ["2"], lat: 39.4750, lon: -0.3600),
    ]

    private func transit() -> TransitData {
        func route(_ ids: [String]) -> BusRoute {
            let direction = RouteDirection(shapes: [], stops: ids)
            return BusRoute(ida: direction, vuelta: RouteDirection(shapes: [], stops: ids.reversed()))
        }
        var byId: [String: Stop] = [:]
        for stop in stops { byId[String(stop.id)] = stop }
        return TransitData(stops: stops, stopsById: byId, routes: ["1": route(["1", "2", "3"]), "2": route(["2", "4"])])
    }

    private func planner(waits: [String: Int] = [:]) -> JourneyPlanner {
        JourneyPlanner(
            transit: transit(),
            streetWalk: { a, b in
                let d = TransitMotion.distanceMeters(a, b)
                return (d, d) // 1 m/s
            },
            nextBus: { stop, line in waits["\(stop):\(line)"] }
        )
    }

    func testDirectRide() async {
        let a = stops[0], c = stops[2]
        let options = await planner(waits: ["1:1": 2]).plan(from: LonLat(lon: a.lon, lat: a.lat), to: LonLat(lon: c.lon, lat: c.lat))
        let direct = options.first { $0.transfers == 0 && $0.legs[1].alightStopId == 3 }
        XCTAssertNotNil(direct)
        XCTAssertEqual(direct?.legs[1].line, "1")
        XCTAssertEqual(direct?.legs[1].direction, "ida")
        XCTAssertEqual(direct?.legs[1].stops, 2)
        XCTAssertEqual(direct?.legs[1].waitMinutes, 2)
        XCTAssertEqual(direct?.legs[1].towards, "C")
    }

    func testOneTransfer() async {
        let a = stops[0], d = stops[3]
        // The destination is ~1.7 km from A but next to D: only 1 → 2 gets there.
        let options = await planner().plan(from: LonLat(lon: a.lon, lat: a.lat), to: LonLat(lon: d.lon, lat: d.lat), maxWalk: 400)
        let transfer = options.first { $0.transfers == 1 }
        XCTAssertNotNil(transfer)
        XCTAssertEqual(transfer?.legs.filter { !$0.walk }.map { $0.line ?? "" }, ["1", "2"])
        XCTAssertEqual(transfer?.legs[1].alightStopId, 2)
        XCTAssertEqual(transfer?.legs[2].waitMinutes, JourneyPlanner.defaultWait)
    }

    func testNoOptionsWhenTooFar() async {
        let options = await planner().plan(from: LonLat(lon: 0, lat: 0), to: LonLat(lon: 1, lat: 1))
        XCTAssertTrue(options.isEmpty)
    }
}
