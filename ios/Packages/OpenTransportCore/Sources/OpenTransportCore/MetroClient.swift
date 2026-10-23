import Foundation

/// Metrovalencia part of EmtRepository.kt: stations, live arrivals and FGV
/// incidents.
public final class MetroClient: Sendable {
    public init() {}

    /// Stations (name, lines, street) from the open GTFS stop list.
    public func stations() async -> [Place] {
        guard let text = try? await HTTP.get(URL(string: Self.stopsURL)!, headers: ["User-Agent": Self.webUserAgent]) else {
            return []
        }
        return Self.parseStations(text)
    }

    /// Live arrivals at a station (metroapi wrapper, no auth). Lines come as "L1".
    public func arrivals(stationId: Int) async -> [Arrival] {
        guard let text = try? await HTTP.get(URL(string: "\(Self.metroAPI)/prevision/\(stationId)/parse")!,
                                             headers: ["User-Agent": Self.metroAPIUserAgent]) else { return [] }
        return Self.parseArrivals(text)
    }

    /// Official FGV incident feeds (line incidents and station accessibility).
    /// - Parameters:
    ///   - locale: FGV translation locale to prefer; English is the fallback.
    ///   - stationNames: GTFS stop_id → station name, for accessibility items.
    public func incidents(locale: String, stationNames: [Int: String]) async -> [Incident] {
        let headers = ["Accept": "application/json", "User-Agent": "okhttp/4.10.0"]
        async let lines = try? HTTP.get(URL(string: "\(Self.fgvAPI)/incidencias")!, headers: headers)
        async let access = try? HTTP.get(URL(string: "\(Self.fgvAPI)/incidencias_accesibilidad")!, headers: headers)
        let lineText = await lines
        let accessText = await access
        return Self.parseLineIncidents(lineText ?? "", locale: locale)
            + Self.parseAccessibilityIncidents(accessText ?? "", locale: locale, stationNames: stationNames)
    }

    // MARK: - Parsing

    static func parseStations(_ text: String) -> [Place] {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let stops = root["stops"] as? [[String: Any]]
        else { return [] }
        return stops.compactMap { item in
            guard let id = jsonInt(item["stop_id"]), let lat = jsonDouble(item["stop_lat"]),
                  let lon = jsonDouble(item["stop_lon"]) else { return nil }
            return Place(id: "mt-\(id)", network: .metro, name: item["stop_name"] as? String ?? "", lat: lat, lon: lon,
                         lines: jsonStrings(item["lines"]).map { "M\($0)" }, detail: item["street_name"] as? String ?? "")
        }
    }

    static func parseArrivals(_ text: String) -> [Arrival] {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let items = root["previsiones"] as? [[String: Any]]
        else { return [] }
        return items.map { item in
            let seconds = jsonInt(item["seconds"]) ?? -1
            let minutes = seconds >= 0 ? "\(max(1, seconds / 60)) min." : String((item["hora"] as? String ?? "").prefix(5))
            return Arrival(line: "L\(jsonInt(item["line"]) ?? 0)", destination: item["destino"] as? String ?? "", minutes: minutes)
        }
    }

    /// FGV line ids 42…51 are Metrovalencia lines 1…10 (best effort, as on Android).
    static func lineNumber(fgvLineId: Int) -> String {
        (42...51).contains(fgvLineId) ? String(fgvLineId - 41) : String(fgvLineId)
    }

    /// Translation per incident id as (title, description), preferring `locale`.
    static func translations(_ value: Any?, locale: String) -> [Int: (String, String)] {
        guard let items = value as? [[String: Any]] else { return [:] }
        var preferred: [Int: (String, String)] = [:]
        var english: [Int: (String, String)] = [:]
        for item in items {
            guard let id = jsonInt(item["incidencia_id"]) else { continue }
            let pair = ((item["titulo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        (item["descripcion"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            let itemLocale = (item["locale"] as? String ?? "").uppercased()
            if itemLocale == locale.uppercased() { preferred[id] = pair }
            if itemLocale == "EN" { english[id] = pair }
        }
        return english.merging(preferred) { _, new in new }
    }

    static func parseLineIncidents(_ text: String, locale: String) -> [Incident] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [] }
        let texts = translations(root["incidencias_translations"], locale: locale)
        var seen = Set<String>()
        var out: [Incident] = []
        for item in root["incidencias"] as? [[String: Any]] ?? [] {
            let line = lineNumber(fgvLineId: jsonInt(item["linea_id"]) ?? 0)
            let (title, description) = jsonInt(item["id"]).flatMap { texts[$0] } ?? ("", "")
            guard seen.insert("\(line):\(title)").inserted else { continue }
            out.append(Incident(title: title.isEmpty ? "Metrovalencia" : title, date: "", lines: [line],
                                network: .metro, detail: description))
        }
        return out
    }

    static func parseAccessibilityIncidents(_ text: String, locale: String, stationNames: [Int: String]) -> [Incident] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [] }
        let texts = translations(root["incidencias_accesibilidad_translations"], locale: locale)
        var seen = Set<Int>()
        var out: [Incident] = []
        for item in root["incidencias_accesibilidad"] as? [[String: Any]] ?? [] {
            let station = jsonInt(item["estacion_id"]) ?? 0
            guard seen.insert(station).inserted else { continue }
            let (title, description) = jsonInt(item["id"]).flatMap { texts[$0] } ?? ("", "")
            let detail = [description, stationNames[station] ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(Incident(title: title.isEmpty ? "♿︎" : title, date: "", lines: [], network: .metro, detail: detail))
        }
        return out
    }

    static let stopsURL = "https://www.wiilink24.com/extras/locations.json"
    static let metroAPI = "https://metroapi.alexbadi.es"
    static let fgvAPI = "https://www.fgv.es/fgv/app/en/api/v1/V"
    static let metroAPIUserAgent = "EMT-RealTime/1.0 (api; contact=alex@example.com)"
    static let webUserAgent = "Mozilla/5.0 (Android) EMT Valencia"
}
