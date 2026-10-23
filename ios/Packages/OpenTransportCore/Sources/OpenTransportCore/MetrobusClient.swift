import Foundation

/// One scheduled Metrobús departure in the day's timetable.
public struct MetrobusTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int
    public let line: String
    public let destination: String
}

/// A Metrobús line's shapes and brand colour, for drawing it on the map.
public struct MetrobusRoute: Sendable {
    public let line: String
    public let color: Int
    public let shapes: [[LonLat]]
}

/// Metrobús part of EmtRepository.kt (Softour API used by MetGo València).
public final class MetrobusClient: Sendable {
    public init() {}

    /// Stops within `radius` metres of a point (the API has no bulk list).
    public func stops(lat: Double, lon: Double, radius: Int = 7000) async -> [Place] {
        let body = #"{"radius":\#(radius),"lat":\#(lat),"lon":\#(lon)}"#
        var headers = Self.headers
        headers["Content-Type"] = "application/json"
        guard let text = try? await HTTP.post(URL(string: "\(Self.api)/stops/near")!, body: Data(body.utf8), headers: headers) else {
            return []
        }
        return Self.parseStops(text)
    }

    /// Live next arrival (and occupancy) per line at a stop code.
    public func arrivals(code: String) async -> [Arrival] {
        guard let text = try? await get("/estimacion/ocupacion/\(code)") else { return [] }
        return Self.parseOccupancy(text)
    }

    /// The whole day's timetable for a stop code.
    public func schedule(code: String, date: Date = Date()) async -> [MetrobusTime] {
        guard let text = try? await get("/stops/code/\(code)/times?date=\(Self.dayFormat.string(from: date))") else { return [] }
        return Self.parseSchedule(text)
    }

    /// Shapes of just the given lines ("MB1"…), used when a stop is selected.
    public func routes(for lines: [String]) async -> [MetrobusRoute] {
        guard !lines.isEmpty, let text = try? await get("/old/routes"),
              let routes = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        var out: [MetrobusRoute] = []
        for route in routes {
            let line = "MB" + (route["route_short_name"] as? String ?? jsonInt(route["route_short_name"]).map(String.init) ?? "")
            guard lines.contains(line), let id = route["route_id"].map({ "\($0)" }) else { continue }
            let concesion = route["concesion"].map { "\($0)" } ?? ""
            let color = Int((route["route_color"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
                ?? 0x0EA5E9
            var shapes: [[LonLat]] = []
            for direction in 0...1 {
                guard let geo = try? await get("/routes/\(id)/shapes?direction=\(direction)&concesion=\(concesion)") else { continue }
                shapes += Self.parseShapes(geo)
            }
            out.append(MetrobusRoute(line: line, color: color, shapes: shapes))
        }
        return out
    }

    /// Service notices scraped from metgovalencia.com (title + PDF link).
    public func incidents() async -> [Incident] {
        guard let html = try? await HTTP.get(URL(string: "https://metgovalencia.com/avisos-de-lineas/")!,
                                             headers: ["User-Agent": "Mozilla/5.0"]) else { return [] }
        return Self.parseIncidents(html)
    }

    private func get(_ path: String) async throws -> String {
        try await HTTP.get(URL(string: Self.api + path)!, headers: Self.headers)
    }

    // MARK: - Parsing

    static func parseStops(_ text: String) -> [Place] {
        guard let items = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item["stop_name"] as? String, !name.isEmpty,
                  let lat = jsonDouble(item["stop_lat"]), let lon = jsonDouble(item["stop_lon"]) else { return nil }
            let code = item["stop_code"].map { "\($0)" } ?? ""
            return Place(id: "mb-\(code)", network: .metrobus, name: name, lat: lat, lon: lon,
                         detail: item["concesion"].map { "\($0)" } ?? "")
        }
    }

    static func parseOccupancy(_ text: String) -> [Arrival] {
        guard let items = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        var out: [(Int, Arrival)] = []
        for item in items {
            guard let estimation = (item["estimations"] as? [[String: Any]])?.first,
                  let minutes = jsonInt(estimation["minutesToArrival"]), minutes >= 0 else { continue }
            let occupancy = estimation["ocupacion"] as? String ?? ""
            let line = "MB" + (item["line"].map { "\($0)" } ?? "")
            out.append((minutes, Arrival(line: line, destination: item["route"] as? String ?? "",
                                         minutes: occupancy.isEmpty ? "\(minutes) min" : "\(minutes) min · \(occupancy)")))
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func parseSchedule(_ text: String) -> [MetrobusTime] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [] }
        var out: [MetrobusTime] = []
        for (key, value) in root {
            guard let hour = Int(key), let items = value as? [[String: Any]] else { continue }
            for item in items {
                guard let minute = jsonInt(item["minute"]) else { continue }
                let line = "MB" + (item["route_short_name"].map { "\($0)" } ?? "")
                out.append(MetrobusTime(hour: hour, minute: minute, line: line, destination: item["direction"] as? String ?? ""))
            }
        }
        return out.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    static func parseShapes(_ text: String) -> [[LonLat]] {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else { return [] }
        return features.compactMap { feature in
            let coords = (feature["geometry"] as? [String: Any])?["coordinates"] as? [[Any]] ?? []
            let shape = coords.compactMap { raw -> LonLat? in
                let p = raw.compactMap(jsonDouble)
                return p.count >= 2 ? LonLat(lon: p[0], lat: p[1]) : nil
            }
            return shape.count >= 2 ? shape : nil
        }
    }

    static func parseIncidents(_ html: String) -> [Incident] {
        var seen = Set<String>()
        var out: [Incident] = []
        for match in html.matches(of: #"<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            let href = match[1]
            let text = match[2].htmlText
            guard href.contains("/wp-content/uploads/"), text.count > 4, seen.insert(text).inserted else { continue }
            out.append(Incident(title: text, date: "", lines: [], network: .metrobus, url: href))
        }
        return out
    }

    // Same values as EmtRepository.kt.
    static let api = "https://api.softoursistemas.com/metrobus"
    static let headers = [
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Linux; Android 17; Pixel 8a)",
        "x-requested-with": "com.softoursistemas.metgovalencia",
        "Origin": "https://localhost",
        "Referer": "https://localhost/",
    ]

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
