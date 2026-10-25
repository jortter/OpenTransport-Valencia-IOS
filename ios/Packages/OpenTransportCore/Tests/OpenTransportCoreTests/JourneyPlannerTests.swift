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

    /// EMT's "no estimate" came through as Int.max and crashed the planner.
    func testUnknownWaitDoesNotOverflow() async {
        let a = stops[0], c = stops[2]
        let options = await planner(waits: ["1:1": Int.max]).plan(from: LonLat(lon: a.lon, lat: a.lat), to: LonLat(lon: c.lon, lat: c.lat))
        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.allSatisfy { $0.totalMinutes < 200 })
    }

    /// EMT line 1 to B, then a 100 m walk to Metrobús stop M for MB1 to N.
    func testWalkingTransferToAnotherNetwork() async {
        let emtA = Stop(id: 1, name: "A", lines: ["1"], lat: 39.4700, lon: -0.3800)
        let emtB = Stop(id: 2, name: "B", lines: ["1"], lat: 39.4800, lon: -0.3800)
        let mbM = Stop(id: 2_000_000, name: "M", lines: ["MB1"], lat: 39.4809, lon: -0.3800)
        let mbN = Stop(id: 2_000_001, name: "N", lines: ["MB1"], lat: 39.5200, lon: -0.3800)
        let all = [emtA, emtB, mbM, mbN]
        var byId: [String: Stop] = [:]
        for stop in all { byId[String(stop.id)] = stop }
        let routes = [
            "1": BusRoute(ida: RouteDirection(shapes: [], stops: ["1", "2"]), vuelta: RouteDirection(shapes: [], stops: ["2", "1"])),
            "MB1": BusRoute(ida: RouteDirection(shapes: [], stops: ["2000000", "2000001"]),
                            vuelta: RouteDirection(shapes: [], stops: ["2000001", "2000000"])),
        ]
        let planner = JourneyPlanner(transit: TransitData(stops: all, stopsById: byId, routes: routes),
                                     streetWalk: { a, b in let d = TransitMotion.distanceMeters(a, b); return (d, d) },
                                     nextBus: { _, _ in 2 })
        let options = await planner.plan(from: LonLat(lon: emtA.lon, lat: emtA.lat), to: LonLat(lon: mbN.lon, lat: mbN.lat))
        let option = options.first { $0.transfers == 1 }
        XCTAssertNotNil(option)
        XCTAssertEqual(option?.legs.compactMap(\.line), ["1", "MB1"])
        // walk to A, ride 1, walk B → M, ride MB1, walk to the destination
        XCTAssertEqual(option?.legs.map(\.walk), [true, false, true, false, true])
        XCTAssertEqual(option?.legs[2].toStop, "M")
    }

    func testNeighboursOnlyAcrossNetworks() {
        let stops = [Stop(id: 1, name: "E1", lines: [], lat: 39.47, lon: -0.38),
                     Stop(id: 2, name: "E2", lines: [], lat: 39.4705, lon: -0.38),
                     Stop(id: 1_000_000, name: "Metro", lines: [], lat: 39.4702, lon: -0.38),
                     Stop(id: 2_000_000, name: "Far", lines: [], lat: 39.49, lon: -0.38)]
        let near = JourneyPlanner.neighbours(of: stops, within: 300)
        XCTAssertEqual(near[1]?.map(\.stop.id), [1_000_000]) // not the other EMT stop, not the far one
        XCTAssertEqual(Set(near[1_000_000]?.map(\.stop.id) ?? []), [1, 2])
        XCTAssertNil(near[2_000_000])
    }
}
