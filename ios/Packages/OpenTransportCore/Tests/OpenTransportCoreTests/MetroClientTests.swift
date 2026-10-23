import XCTest
@testable import OpenTransportCore

final class MetroClientTests: XCTestCase {
    func testParsesStations() {
        let json = #"{"stops":[{"stop_id":20,"stop_name":"València Sud","stop_lat":39.45,"stop_lon":-0.39,"lines":[1,2,7],"street_name":"Av. Sud"}]}"#
        let places = MetroClient.parseStations(json)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].id, "mt-20")
        XCTAssertEqual(places[0].network, .metro)
        XCTAssertEqual(places[0].lines, ["M1", "M2", "M7"])
        XCTAssertEqual(places[0].detail, "Av. Sud")
    }

    func testParsesArrivals() {
        let json = #"{"previsiones":[{"line":3,"destino":"Aeroport","seconds":150},{"line":5,"destino":"Marítim","seconds":-1,"hora":"12:05:00"}]}"#
        let arrivals = MetroClient.parseArrivals(json)
        XCTAssertEqual(arrivals, [
            Arrival(line: "L3", destination: "Aeroport", minutes: "2 min."),
            Arrival(line: "L5", destination: "Marítim", minutes: "12:05"),
        ])
        XCTAssertTrue(MetroClient.parseArrivals("not json").isEmpty)
    }

    func testLineIncidentsPreferLocaleThenEnglish() {
        let json = """
        {"incidencias":[{"id":1,"linea_id":44},{"id":2,"linea_id":45},{"id":3,"linea_id":44}],
         "incidencias_translations":[
           {"incidencia_id":1,"locale":"EN","titulo":"Works","descripcion":"Bus replacement"},
           {"incidencia_id":1,"locale":"ES","titulo":"Obras","descripcion":"Bus sustitutorio"},
           {"incidencia_id":2,"locale":"EN","titulo":"Delay","descripcion":""},
           {"incidencia_id":3,"locale":"ES","titulo":"Obras","descripcion":"Bus sustitutorio"}]}
        """
        let incidents = MetroClient.parseLineIncidents(json, locale: "es")
        // Incident 3 duplicates 1 (same line and title) and is dropped.
        XCTAssertEqual(incidents.map(\.title), ["Obras", "Delay"])
        XCTAssertEqual(incidents[0].lines, ["3"])
        XCTAssertEqual(incidents[1].lines, ["4"])
        XCTAssertEqual(incidents[0].network, .metro)
    }

    func testAccessibilityIncidents() {
        let json = """
        {"incidencias_accesibilidad":[{"id":9,"estacion_id":20},{"id":10,"estacion_id":20}],
         "incidencias_accesibilidad_translations":[{"incidencia_id":9,"locale":"EN","titulo":"Lift out of service","descripcion":"Platform 1"}]}
        """
        let incidents = MetroClient.parseAccessibilityIncidents(json, locale: "en", stationNames: [20: "València Sud"])
        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(incidents[0].title, "Lift out of service")
        XCTAssertEqual(incidents[0].detail, "Platform 1 · València Sud")
    }

    func testFgvLineNumbers() {
        XCTAssertEqual(MetroClient.lineNumber(fgvLineId: 42), "1")
        XCTAssertEqual(MetroClient.lineNumber(fgvLineId: 51), "10")
        XCTAssertEqual(MetroClient.lineNumber(fgvLineId: 7), "7")
    }
}
