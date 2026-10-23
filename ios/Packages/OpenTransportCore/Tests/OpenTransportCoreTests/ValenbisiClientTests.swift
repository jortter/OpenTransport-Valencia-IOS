import XCTest
@testable import OpenTransportCore

final class ValenbisiClientTests: XCTestCase {
    func testParsesStations() {
        let json = """
        [{"number":12,"name":"012_PLAZA_DEL_AYUNTAMIENTO","address":"Pl. Ajuntament","status":"OPEN",
          "position":{"latitude":39.47,"longitude":-0.376},
          "totalStands":{"availabilities":{"bikes":5,"stands":15,"mechanicalBikes":3,"electricalBikes":2}}},
         {"number":13,"name":"X","status":"CLOSED","position":{"latitude":39.4,"longitude":-0.3}},
         {"number":14,"name":"no position"}]
        """
        let places = ValenbisiClient.parseStations(json)
        XCTAssertEqual(places.count, 2)
        let first = places[0]
        XCTAssertEqual(first.id, "vb-12")
        XCTAssertEqual(first.name, "012 PLAZA DEL AYUNTAMIENTO")
        XCTAssertEqual(first.available, 5)
        XCTAssertEqual(first.free, 15)
        XCTAssertEqual(first.mechanical, 3)
        XCTAssertEqual(first.electric, 2)
        XCTAssertTrue(first.open)
        XCTAssertFalse(places[1].open)
        XCTAssertEqual(places[1].available, -1)
    }

    func testParsesBikesSortedByStand() {
        let json = #"[{"number":900,"standNumber":7,"type":"ELECTRIC","rating":{"value":80,"count":3}},{"number":901,"standNumber":2,"type":"MECHANICAL"}]"#
        let bikes = ValenbisiClient.parseBikes(json)
        XCTAssertEqual(bikes.map(\.stand), [2, 7])
        XCTAssertEqual(bikes[1].rating, 80)
        XCTAssertEqual(bikes[1].ratings, 3)
        XCTAssertEqual(bikes[0].ratings, 0)
    }
}
