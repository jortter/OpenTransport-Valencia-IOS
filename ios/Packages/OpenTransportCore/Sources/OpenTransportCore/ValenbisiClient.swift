import Foundation

/// One docked Valenbisi bike: which stand, its type and its user rating.
public struct Bike: Hashable, Sendable {
    public let number: Int
    public let stand: Int
    public let type: String
    /// 0…100 (Android shows `rating / 20` stars).
    public let rating: Double
    public let ratings: Int
}

/// Valenbisi part of EmtRepository.kt: stations from JCDecaux and the docked
/// bikes of one station from Cyclocity.
public final class ValenbisiClient: @unchecked Sendable {
    private let lock = NSLock()
    private var token: (Date, String)?

    public init() {}

    /// Stations with live bikes/docks (JCDecaux public API).
    public func stations() async -> [Place] {
        guard let text = try? await HTTP.get(URL(string: Self.stationsURL)!, headers: ["User-Agent": Self.webUserAgent]) else {
            return []
        }
        return Self.parseStations(text)
    }

    /// Docked bikes at a station (Cyclocity, with a short-lived client token).
    public func bikes(station: Int) async -> [Bike] {
        guard let token = await clientToken() else { return [] }
        let url = URL(string: "\(Self.cyclocityAPI)/contracts/valence/bikes?stationNumber=\(station)")!
        guard let text = try? await HTTP.get(url, headers: [
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/vnd.bikes.v4+json",
            "Content-Type": "application/vnd.bikes.v4+json",
            "Authorization": "Taknv1 \(token)",
            "Origin": "https://www.valenbisi.es",
            "Referer": "https://www.valenbisi.es/",
        ]) else { return [] }
        return Self.parseBikes(text)
    }

    private func clientToken() async -> String? {
        if let cached = cachedToken(), Date().timeIntervalSince(cached.0) < 10 * 60 { return cached.1 }
        let body = #"{"code":"vls.web.valence:PRD","key":"5baec26027069c8ff4358f7f8faf43e0ce2c1e32f6d919cc6006a4ee6bfdf5ac"}"#
        guard
            let text = try? await HTTP.post(URL(string: "\(Self.cyclocityAPI)/auth/environments/PRD/client_tokens")!,
                                            body: Data(body.utf8), headers: ["Content-Type": "application/json"]),
            let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let fresh = root["accessToken"] as? String, !fresh.isEmpty
        else { return nil }
        store(fresh)
        return fresh
    }

    // Synchronous so the lock is never held across an await.
    private func cachedToken() -> (Date, String)? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    private func store(_ fresh: String) {
        lock.lock()
        defer { lock.unlock() }
        token = (Date(), fresh)
    }

    // MARK: - Parsing

    static func parseStations(_ text: String) -> [Place] {
        guard let items = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let position = item["position"] as? [String: Any],
                  let lat = jsonDouble(position["latitude"]), let lon = jsonDouble(position["longitude"]) else { return nil }
            // v3 nests the counts under totalStands.availabilities.
            let availability = (item["totalStands"] as? [String: Any])?["availabilities"] as? [String: Any] ?? [:]
            let name = (item["name"] as? String ?? "").replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return Place(
                id: "vb-\(jsonInt(item["number"]) ?? 0)", network: .valenbisi, name: name, lat: lat, lon: lon,
                detail: item["address"] as? String ?? "",
                available: jsonInt(availability["bikes"]) ?? -1,
                free: jsonInt(availability["stands"]) ?? -1,
                open: (item["status"] as? String ?? "").uppercased() == "OPEN",
                mechanical: jsonInt(availability["mechanicalBikes"]) ?? -1,
                electric: jsonInt(availability["electricalBikes"]) ?? -1
            )
        }
    }

    static func parseBikes(_ text: String) -> [Bike] {
        guard let items = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { return [] }
        return items.map { item in
            let rating = item["rating"] as? [String: Any] ?? [:]
            return Bike(number: jsonInt(item["number"]) ?? 0, stand: jsonInt(item["standNumber"]) ?? 0,
                        type: item["type"] as? String ?? "", rating: jsonDouble(rating["value"]) ?? 0,
                        ratings: jsonInt(rating["count"]) ?? 0)
        }.sorted { $0.stand < $1.stand }
    }

    // Same values as EmtRepository.kt.
    static let stationsURL = "https://api.jcdecaux.com/vls/v3/stations?apiKey=frifk0jbxfefqqniqez09tw4jvk37wyf823b5j1i&contract=valence"
    static let cyclocityAPI = "https://api.cyclocity.fr"
    static let webUserAgent = "Mozilla/5.0 (Android) EMT Valencia"
}
