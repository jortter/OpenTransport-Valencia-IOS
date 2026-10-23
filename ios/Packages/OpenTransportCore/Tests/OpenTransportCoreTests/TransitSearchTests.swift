import XCTest
@testable import OpenTransportCore

final class TransitSearchTests: XCTestCase {
    private let stops = [
        Stop(id: 7, name: "Doctor J.J. Dòmine - Edifici del Rellotge (7)", lines: ["19"], lat: 0, lon: 0),
        Stop(id: 711, name: "Marqués del Túria - Joaquín Costa (711)", lines: ["79"], lat: 0, lon: 0),
        Stop(id: 1_000_001, name: "Àngel Guimerà", lines: ["M1"], lat: 0, lon: 0, metro: true),
    ]

    func testByNumber() {
        XCTAssertEqual(TransitSearch.stops(stops, query: "71").map(\.id), [711])
        XCTAssertEqual(TransitSearch.stops(stops, query: " 7 ").map(\.id), [7, 711])
    }

    func testByWordsInAnyOrder() {
        XCTAssertEqual(TransitSearch.stops(stops, query: "costa túria").map(\.id), [711])
        XCTAssertTrue(TransitSearch.stops(stops, query: "").isEmpty)
    }

    func testMetroExcludedByDefault() {
        XCTAssertTrue(TransitSearch.stops(stops, query: "guimerà").isEmpty)
        XCTAssertEqual(TransitSearch.stops(stops, query: "guimerà", includeMetro: true).count, 1)
    }

    func testLinesNumericFirst() {
        let direction = RouteDirection(shapes: [], stops: [])
        let route = BusRoute(ida: direction, vuelta: direction)
        let transit = TransitData(stops: [], stopsById: [:], routes: ["19": route, "1": route, "N1": route, "10": route, "M1": route])
        XCTAssertEqual(TransitSearch.lines(transit, query: "1"), ["1", "10", "19", "M1", "N1"])
    }
}
