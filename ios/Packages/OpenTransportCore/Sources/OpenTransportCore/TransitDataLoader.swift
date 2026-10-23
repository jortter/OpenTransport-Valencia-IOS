import Foundation

/// Port of `TransitDataLoader` in TransitData.kt. Reads the same bundled files
/// (`stops.json`, `routes.json`, `metrovalencia.geojson`) used by Android.
public enum TransitDataLoader {
    public enum LoadError: Error {
        case missing(String)
        case malformed(String)
    }

    static let metroIdBase = 1_000_000

    /// - Parameter directory: folder that contains the Android `assets` files.
    public static func load(from directory: URL) throws -> TransitData {
        let stops = try parseStops(read(directory, "stops.json"))
        let routes = try parseRoutes(read(directory, "routes.json"))
        // Metrovalencia: merge its stations and route shapes into the same graph
        // so the planner can route over them like EMT stops.
        let metro = (try? read(directory, "metrovalencia.geojson")).map(parseMetro) ?? ([], [:])
        // Some EMT stops are physically Metro stations (same name): flag them.
        let metroNames = Set(metro.0.map { $0.name.lowercased() })
        let tagged = stops.map { stop -> Stop in
            var copy = stop
            if metroNames.contains(stop.name.lowercased()) { copy.metro = true }
            return copy
        }
        let all = tagged + metro.0
        var byId: [String: Stop] = [:]
        for stop in all { byId[String(stop.id)] = stop }
        return TransitData(stops: all, stopsById: byId, routes: routes.merging(metro.1) { _, new in new })
    }

    private static func read(_ directory: URL, _ name: String) throws -> Data {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { throw LoadError.missing(name) }
        return data
    }

    // MARK: - stops.json

    private struct RawStop: Decodable {
        let id: Int
        let nombre: String
        let lineas: [String]
        let lat: Double
        let lon: Double
    }

    static func parseStops(_ data: Data) throws -> [Stop] {
        try JSONDecoder().decode([RawStop].self, from: data).map {
            Stop(id: $0.id, name: $0.nombre, lines: $0.lineas, lat: $0.lat, lon: $0.lon)
        }
    }

    // MARK: - routes.json

    private struct RawDirection: Decodable {
        let shapes: [[[Double]]] // source JSON is [lat, lon]
        let stops: [String]
    }

    private struct RawRoute: Decodable {
        let ida: RawDirection
        let vuelta: RawDirection
    }

    static func parseRoutes(_ data: Data) throws -> [String: BusRoute] {
        let raw = try JSONDecoder().decode([String: RawRoute].self, from: data)
        func direction(_ d: RawDirection) -> RouteDirection {
            RouteDirection(
                shapes: d.shapes.map { shape in
                    shape.compactMap { p in p.count >= 2 ? LonLat(lon: p[1], lat: p[0]) : nil }
                },
                stops: d.stops
            )
        }
        return raw.mapValues { BusRoute(ida: direction($0.ida), vuelta: direction($0.vuelta)) }
    }

    // MARK: - metrovalencia.geojson

    static func parseMetro(_ data: Data) -> ([Stop], [String: BusRoute]) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { return ([], [:]) }

        var stations: [String: Stop] = [:]
        var order: [String] = []
        var lineStrings: [[String: Any]] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any] else { continue }
            let properties = feature["properties"] as? [String: Any] ?? [:]
            switch geometry["type"] as? String {
            case "Point":
                guard
                    let coords = (geometry["coordinates"] as? [Any])?.compactMap(jsonDouble), coords.count >= 2,
                    let name = properties["stop_name"] as? String, !name.isEmpty
                else { continue }
                let lines = jsonStrings(properties["lines"]).map { "M\($0)" }
                // Same id rule as Android: base + map size before inserting.
                let id = metroIdBase + stations.count
                if stations[name] == nil { order.append(name) }
                stations[name] = Stop(id: id, name: name, lines: lines,
                                      lat: coords[1], lon: coords[0], metro: true)
            case "LineString":
                lineStrings.append(feature)
            default:
                continue
            }
        }

        var groups: [Int: [[String: Any]]] = [:]
        var groupOrder: [Int] = []
        for feature in lineStrings {
            let line = jsonInt((feature["properties"] as? [String: Any])?["line"]) ?? 0
            guard line != 0 else { continue }
            if groups[line] == nil { groupOrder.append(line) }
            groups[line, default: []].append(feature)
        }

        var routes: [String: BusRoute] = [:]
        for line in groupOrder {
            let directions: [RouteDirection] = (groups[line] ?? []).prefix(2).map { feature in
                let coords = (feature["geometry"] as? [String: Any])?["coordinates"] as? [[Any]] ?? []
                let shape = coords.compactMap { raw -> LonLat? in
                    let p = raw.compactMap(jsonDouble)
                    return p.count >= 2 ? LonLat(lon: p[0], lat: p[1]) : nil
                }
                let names = jsonStrings((feature["properties"] as? [String: Any])?["stops"])
                return RouteDirection(shapes: [shape], stops: names.compactMap { stations[$0].map { String($0.id) } })
            }
            if let first = directions.first {
                routes["M\(line)"] = BusRoute(ida: first, vuelta: directions.count > 1 ? directions[1] : first)
            }
        }
        return (order.compactMap { stations[$0] }, routes)
    }
}

/// Mirrors `JSONArray.getString`, which also stringifies numbers.
func jsonStrings(_ value: Any?) -> [String] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { item in
        if let s = item as? String { return s }
        if let n = item as? NSNumber { return n.stringValue }
        return nil
    }
}

func jsonInt(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let d = value as? Double { return Int(d) }
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String { return Int(s) }
    return nil
}

func jsonDouble(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String { return Double(s) }
    return nil
}

/// Extra Metrovalencia facts from the bundled geojson: GTFS station names
/// (for FGV accessibility alerts) and each line's brand colour.
public struct MetroAssets: Sendable {
    public let stationNames: [Int: String]
    /// "M1" → 0xFEC601
    public let lineColors: [String: Int]

    public static func load(from directory: URL) -> MetroAssets {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("metrovalencia.geojson")) else {
            return MetroAssets(stationNames: [:], lineColors: [:])
        }
        return parse(data)
    }

    static func parse(_ data: Data) -> MetroAssets {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { return MetroAssets(stationNames: [:], lineColors: [:]) }
        var names: [Int: String] = [:]
        var colors: [String: Int] = [:]
        for feature in features {
            let properties = feature["properties"] as? [String: Any] ?? [:]
            switch (feature["geometry"] as? [String: Any])?["type"] as? String {
            case "Point":
                if let id = jsonInt(properties["stop_id"]), let name = properties["stop_name"] as? String { names[id] = name }
            case "LineString":
                if let line = jsonInt(properties["line"]), let hex = properties["color"] as? String,
                   let value = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) {
                    colors["M\(line)"] = value
                }
            default:
                break
            }
        }
        return MetroAssets(stationNames: names, lineColors: colors)
    }
}
