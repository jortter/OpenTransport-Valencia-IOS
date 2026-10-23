import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// EMT part of EmtRepository.kt: live buses, official estimations, stop info
/// and service incidents.
public final class EmtClient: @unchecked Sendable {
    private let data: TransitData
    private let lock = NSLock()
    private var incidentCache: (Date, [Incident])?

    public init(data: TransitData) {
        self.data = data
    }

    // MARK: - Live buses

    public func buses(line: String) async -> [BusFix] {
        (try? await fetchBuses(line: line)) ?? []
    }

    /// Like `buses(line:)` but throws on network errors, so a live view can keep
    /// the last positions instead of wiping the map on a dropped request.
    public func fetchBuses(line: String) async throws -> [BusFix] {
        let raw = try await request("/buses/linea.php", ["usuario": Self.user, "linea": line])
        return Self.parseBuses(raw, line: line, routes: data.routes)
    }

    static func parseBuses(_ raw: String, line: String, routes: [String: BusRoute]) -> [BusFix] {
        guard
            let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
            let array = json["buses"] as? [[String: Any]]
        else { return [] }
        return array.map { item in
            let last = jsonInt(item["pUlt"]) ?? 0
            let next = jsonInt(item["pSig"]) ?? 0
            return BusFix(
                number: jsonInt(item["num"]) ?? 0,
                line: (item["lin"] as? String) ?? jsonInt(item["lin"]).map(String.init) ?? line,
                destination: item["tra"] as? String ?? "",
                lastStop: last,
                nextStop: next,
                lon: jsonDouble(item["lon"]) ?? .nan,
                lat: jsonDouble(item["lat"]) ?? .nan,
                timestamp: item["ts"] as? String ?? "",
                direction: TransitMotion.direction(routes, line: line, last: last, next: next)
            )
        }
    }

    // MARK: - Stop

    public func stop(id: Int) async -> StopInfo? {
        guard let stop = data.stopsById[String(id)] else { return nil }

        let byLine: [String: [BusFix]] = await withTaskGroup(of: (String, [BusFix]).self) { group in
            for line in stop.lines {
                group.addTask { (line, await self.buses(line: line)) }
            }
            var result: [String: [BusFix]] = [:]
            for await (line, fixes) in group { result[line] = fixes }
            return result
        }

        var arrivals: [Arrival] = []
        var near: [NearBus] = []
        for line in stop.lines {
            let candidates: [(BusFix, String, Double)] = (byLine[line] ?? []).compactMap { bus in
                guard let dir = bus.direction else { return nil }
                let seq = TransitMotion.itinerary(data.routes, line: line, direction: dir)
                guard
                    let iBus = seq.firstIndex(of: String(bus.nextStop)),
                    let iStop = seq.firstIndex(of: String(id)),
                    iBus < iStop
                else { return nil }
                let dist = TransitMotion.distanceMeters(LonLat(lon: bus.lon, lat: bus.lat), LonLat(lon: stop.lon, lat: stop.lat))
                return (bus, dir, dist)
            }
            guard let best = candidates.min(by: { $0.2 < $1.2 }) else { continue }
            let (bus, dir, dist) = best
            let minutes = max(1, Int((dist / 1000 / 18 * 60).rounded()))
            near.append(NearBus(line: line, number: bus.number, lat: bus.lat, lon: bus.lon, direction: dir,
                                minutes: minutes, distanceMeters: (dist * 100).rounded() / 100))
            arrivals.append(Arrival(line: line, destination: bus.destination, minutes: "\(minutes) min.", source: "computed"))
        }

        let official = await estimations(stopId: id)
        let now = Date()
        let result = (official.isEmpty ? arrivals : official).sorted {
            Self.etaMinutes($0, now: now) < Self.etaMinutes($1, now: now)
        }
        return StopInfo(stop: stop, arrivals: result, buses: near.sorted { $0.minutes < $1.minutes })
    }

    public func estimations(stopId: Int) async -> [Arrival] {
        guard let xml = try? await request("/estimaciones/estimacion.php", [
            "idioma": "en", "parada": String(stopId), "adaptados": "false",
        ]) else { return [] }
        return Self.parseEstimations(xml)
    }

    /// Minutes until the next `line` bus at `stopId`, or nil when unknown.
    public func nextBus(stopId: Int, line: String) async -> Int? {
        let now = Date()
        return await estimations(stopId: stopId)
            .filter { $0.line == line }
            .map { Self.etaMinutes($0, now: now) }
            .min()
    }

    // MARK: - Incidents

    public func incidents(force: Bool = false) async -> [Incident] {
        let cached = cachedIncidents()
        if let cached, !force, Date().timeIntervalSince(cached.0) < Self.incidentCacheSeconds { return cached.1 }
        guard let html = try? await HTTP.get(URL(string: "https://www.emtvalencia.es/wp/estado-del-servicio/")!,
                                             headers: ["User-Agent": Self.webUserAgent]) else {
            return cached?.1 ?? []
        }
        let parsed = Self.parseIncidents(html)
        storeIncidents(parsed)
        return parsed
    }

    // Synchronous so NSLock is never held across an await.
    private func cachedIncidents() -> (Date, [Incident])? {
        lock.lock()
        defer { lock.unlock() }
        return incidentCache
    }

    private func storeIncidents(_ incidents: [Incident]) {
        lock.lock()
        defer { lock.unlock() }
        incidentCache = (Date(), incidents)
    }

    static func parseIncidents(_ html: String) -> [Incident] {
        html.matches(of: #"<section class=\"estado-servicio\">(.*?)</section>"#, options: .dotMatchesLineSeparators).map { match in
            let section = match[1]
            let text = section.htmlText
            let date = text.firstMatch(of: #"Desde:\s*([0-9/]+)"#)?[1] ?? ""
            let lines = Set(section.matches(of: #"<img[^>]*alt=\"L[ií]nea\s+([A-Za-z0-9]+)"#).map { normalizeLine($0[1]) })
            let title = section.firstMatch(of: #"<h2[^>]*>\s*<a[^>]*>(.*?)</a>"#, options: .dotMatchesLineSeparators)?[1]
                .replacingRegex("<[^>]+>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                ?? String(text.prefix(160))
            return Incident(title: title, date: date, lines: lines)
        }
    }

    // MARK: - ETA helpers

    public static func etaMinutes(_ a: Arrival, now: Date = Date()) -> Int {
        let m = a.minutes.trimmingCharacters(in: .whitespaces).lowercased()
        if m.hasPrefix("next") { return 0 }
        // Schedules may come as "hh:mm:ss" (in either field); convert to minutes.
        if m.contains(":"), let clock = parseClock(m, now: now) { return clock }
        if let digits = m.firstMatch(of: #"^(\d+)"#)?[1] { return Int(digits) ?? Int.max }
        if let clock = parseClock(a.arrivalTime, now: now) { return clock }
        return Int.max
    }

    /// What to show for an arrival: a minute count, never a raw timestamp.
    public static func etaLabel(_ a: Arrival, now: Date = Date()) -> String {
        let minutes = etaMinutes(a, now: now)
        if minutes != Int.max && (a.minutes.isEmpty || a.minutes.contains(":")) { return "\(minutes) min" }
        if !a.minutes.isEmpty { return a.minutes }
        let time = String(a.arrivalTime.prefix(5))
        return time.isEmpty ? "—" : time
    }

    /// Minutes from now to a "hh:mm[:ss]" clock time.
    static func parseClock(_ value: String, now: Date) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let current = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let target = hour * 60 + minute
        return target >= current ? target - current : target + 1440 - current
    }

    static func normalizeLine(_ line: String) -> String {
        let v = line.trimmingCharacters(in: .whitespaces).uppercased()
        return Int(v).map(String.init) ?? v
    }

    // MARK: - Estimations XML

    static func parseEstimations(_ xml: String) -> [Arrival] {
        guard !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let delegate = EstimationsParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.out
    }

    // MARK: - Transport

    private func request(_ path: String, _ query: [String: String]) async throws -> String {
        var components = URLComponents(string: Self.host + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await HTTP.get(components.url!, headers: [
            "Accept-Charset": "UTF-8",
            "User-Agent": Self.userAgent,
            "X-WSSE": Self.wsse,
            "Content-Type": "application/json; charset=UTF-8",
        ])
    }

    // Same values as EmtRepository.kt.
    static let host = "https://servicios.emtvalencia.es"
    static let user = "7gH8m45w7A"
    static let userAgent = "Dalvik/2.1.0 (Linux; U; Android 17; Pixel 8a Build/CP41.260831.007)"
    static let webUserAgent = "Mozilla/5.0 (Android) EMT Valencia"
    static let wsse = "UsernameToken Username=\"7gH8m45w7A\", PasswordDigest=\"ODdmMzU1OWU4ZDEwZGE0MDllM2E5NzhlZTg3Y2UxMmRjYTQ2N2VmYQ==\", Nonce=\"MjZlNTNjMWIxZmZhMmU4NjE5N2QyYjhkMjgyMGU2YjU=\", Created=\"1790762921\""
    static let incidentCacheSeconds: TimeInterval = 30 * 60
}

private final class EstimationsParser: NSObject, XMLParserDelegate {
    var out: [Arrival] = []
    private var inBus = false
    private var fields: [String: String] = [:]
    private var current: String?
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "bus" {
            inBus = true
            fields = [:]
        } else if inBus, ["linea", "destino", "minutos", "horaLlegada"].contains(elementName) {
            current = elementName
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == current {
            fields[elementName] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            current = nil
        } else if elementName == "bus", inBus {
            let line = fields["linea"] ?? ""
            let dest = fields["destino"] ?? ""
            let minutes = fields["minutos"] ?? ""
            if !line.isEmpty || !dest.isEmpty || !minutes.isEmpty {
                out.append(Arrival(line: line, destination: dest, minutes: minutes, arrivalTime: fields["horaLlegada"] ?? ""))
            }
            inBus = false
        }
    }
}
