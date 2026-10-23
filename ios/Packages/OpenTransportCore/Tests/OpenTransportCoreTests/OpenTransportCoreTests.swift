import XCTest
@testable import OpenTransportCore

final class OpenTransportCoreTests: XCTestCase {
    /// The Android assets folder, shared with the iOS app.
    private var assets: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenTransportCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // OpenTransportCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
            .appendingPathComponent("app/src/main/assets")
    }

    func testLoadsBundledData() throws {
        let data = try TransitDataLoader.load(from: assets)
        XCTAssertGreaterThan(data.stops.count, 1000)
        XCTAssertNotNil(data.stopsById["7"])
        XCTAssertEqual(data.stopsById["7"]?.lines, ["19", "92", "95"])
        XCTAssertNotNil(data.routes["4"])
        XCTAssertFalse(data.routes["4"]!.ida.shapes.isEmpty)
        // Metro stations and lines merged in.
        XCTAssertTrue(data.stops.contains { $0.metro && $0.id >= TransitDataLoader.metroIdBase })
        XCTAssertNotNil(data.routes["M1"])
        XCTAssertFalse(data.routes["M1"]!.ida.stops.isEmpty)
    }

    func testRouteShapesAreLonLat() throws {
        let data = try TransitDataLoader.load(from: assets)
        let point = data.routes["4"]!.ida.shapes[0][0]
        // Valencia is around 39.4N, -0.37E.
        XCTAssertEqual(point.lat, 39.4, accuracy: 0.5)
        XCTAssertEqual(point.lon, -0.37, accuracy: 0.5)
    }

    func testDistanceAndProjection() {
        let a = LonLat(lon: -0.3763, lat: 39.4699)
        let b = LonLat(lon: -0.3763, lat: 39.4799)
        XCTAssertEqual(TransitMotion.distanceMeters(a, b), 1112, accuracy: 5)
        let route = TransitMotion.prepare([a, b])
        let mid = TransitMotion.project(route, LonLat(lon: -0.3763, lat: 39.4749))
        XCTAssertEqual(mid.distanceAlong, route.totalMeters / 2, accuracy: 2)
        XCTAssertEqual(TransitMotion.pointAt(route, route.totalMeters / 2).lat, 39.4749, accuracy: 0.0001)
        XCTAssertEqual(TransitMotion.formatDistance(432), "430 m")
        XCTAssertEqual(TransitMotion.formatDistance(1530), "1.5 km")
    }

    func testDirection() {
        let routes = ["1": BusRoute(ida: RouteDirection(shapes: [], stops: ["1", "2", "3"]),
                                    vuelta: RouteDirection(shapes: [], stops: ["3", "2", "1"]))]
        XCTAssertEqual(TransitMotion.direction(routes, line: "1", last: 1, next: 2), "ida")
        XCTAssertEqual(TransitMotion.direction(routes, line: "1", last: 3, next: 2), "vuelta")
        XCTAssertNil(TransitMotion.direction(routes, line: "9", last: 1, next: 2))
    }

    func testParsesEstimations() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <estimacion><solicitud><parada>7</parada></solicitud>
        <bus><linea>19</linea><destino>Platja Malva-rosa</destino><minutos>4 min.</minutos><horaLlegada>12:04</horaLlegada></bus>
        <bus><linea>92</linea><destino>Pl. Ajuntament</destino><minutos>next</minutos><horaLlegada></horaLlegada></bus>
        </estimacion>
        """
        let arrivals = EmtClient.parseEstimations(xml)
        XCTAssertEqual(arrivals.count, 2)
        XCTAssertEqual(arrivals[0], Arrival(line: "19", destination: "Platja Malva-rosa", minutes: "4 min.", arrivalTime: "12:04"))
        XCTAssertEqual(EmtClient.etaMinutes(arrivals[0]), 4)
        XCTAssertEqual(EmtClient.etaMinutes(arrivals[1]), 0)
        XCTAssertEqual(EmtClient.etaLabel(arrivals[0]), "4 min.")
    }

    func testParsesBuses() {
        let routes = ["19": BusRoute(ida: RouteDirection(shapes: [], stops: ["7", "9"]),
                                     vuelta: RouteDirection(shapes: [], stops: ["9", "7"]))]
        let raw = #"{"buses":[{"num":123,"lin":"19","tra":"Malva-rosa","pUlt":7,"pSig":9,"lon":-0.33,"lat":39.46,"ts":"2026-10-23 12:00:00"}]}"#
        let buses = EmtClient.parseBuses(raw, line: "19", routes: routes)
        XCTAssertEqual(buses.count, 1)
        XCTAssertEqual(buses[0].number, 123)
        XCTAssertEqual(buses[0].direction, "ida")
        XCTAssertEqual(buses[0].lat, 39.46, accuracy: 1e-9)
    }

    func testParsesIncidents() {
        let html = """
        <section class="estado-servicio"><h2><a href="#">Desvío línea 19</a></h2>
        <p>Desde: 20/10/2026</p><img alt="Línea 19"><img alt="Linea 092"></section>
        """
        let incidents = EmtClient.parseIncidents(html)
        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(incidents[0].title, "Desvío línea 19")
        XCTAssertEqual(incidents[0].date, "20/10/2026")
        XCTAssertEqual(incidents[0].lines, ["19", "92"])
    }

    func testStrings() {
        XCTAssertEqual(Strings(.es).map, "Mapa")
        XCTAssertEqual(Strings(.va).saved, "Guardades")
        XCTAssertEqual(Strings(.va).map, "Mapa") // falls back to Spanish
        XCTAssertEqual(Language.of("xx"), .en)
    }

    func testCleanStopName() {
        XCTAssertEqual(cleanStopName("Doctor Lluch - Vicent Gallart (9)"), "Doctor Lluch - Vicent Gallart")
    }
}
