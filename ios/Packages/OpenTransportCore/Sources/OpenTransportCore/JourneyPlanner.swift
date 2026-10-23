import Foundation

// Port of JourneyPlanner.kt.

public struct JourneyLeg: Hashable, Sendable {
    public let walk: Bool
    public let minutes: Int
    public let meters: Int
    public var line: String?
    public var direction: String?
    public var towards: String?
    public var boardStop: String?
    public var alightStop: String?
    public var stops: Int = 0
    public var waitMinutes: Int = 0
    public var toStop: String?
    public var boardStopId: Int?
    public var alightStopId: Int?

    static func walking(minutes: Int, meters: Int, to: String) -> JourneyLeg {
        JourneyLeg(walk: true, minutes: minutes, meters: meters, toStop: to)
    }
}

public struct JourneyOption: Hashable, Sendable {
    public let totalMinutes: Int
    public let walkMeters: Int
    public let transfers: Int
    public let legs: [JourneyLeg]
}

/// Schedule-aware journey planner: rides along the itineraries, walking on
/// streets, scored by the live waiting times supplied through `nextBus`.
/// Pure logic: the walking and waiting lookups are injected.
public final class JourneyPlanner: @unchecked Sendable {
    public typealias StreetWalk = @Sendable (LonLat, LonLat) async -> (meters: Double, seconds: Double)
    public typealias NextBus = @Sendable (Int, String) async -> Int?

    private let transit: TransitData
    private let streetWalk: StreetWalk
    private let nextBus: NextBus
    private var sequence: [String: [String]] = [:]
    private var position: [String: [String: Int]] = [:]

    static let detour = 1.25
    static let rideMetersPerSecond = 5.0
    static let stopMinutes = 1.6
    public static let maxWalkMeters = 1000.0
    static let maxRideStops = 30
    static let transferPenalty = 3.0
    static let defaultWait = 6
    static let maxOptions = 4

    public init(transit: TransitData, streetWalk: @escaping StreetWalk, nextBus: @escaping NextBus) {
        self.transit = transit
        self.streetWalk = streetWalk
        self.nextBus = nextBus
        for (line, route) in transit.routes {
            for (dir, direction) in [("ida", route.ida), ("vuelta", route.vuelta)] {
                sequence[key(line, dir)] = direction.stops
                var index: [String: Int] = [:]
                for (i, stop) in direction.stops.enumerated() where index[stop] == nil { index[stop] = i }
                position[key(line, dir)] = index
            }
        }
    }

    private func key(_ line: String, _ dir: String) -> String { "\(line)|\(dir)" }

    private func linesAt(_ stopId: Int) -> Set<String> { Set(transit.stopsById[String(stopId)]?.lines ?? []) }

    private func stopsNear(_ point: LonLat, maxWalk: Double, limit: Int = 10) -> [Stop] {
        transit.stops
            .map { ($0, TransitMotion.distanceMeters(point, LonLat(lon: $0.lon, lat: $0.lat))) }
            .filter { $0.1 <= maxWalk * Self.detour }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func ride(_ line: String, _ dir: String, from: Int, to: Int) -> Double {
        let seq = sequence[key(line, dir)] ?? []
        var meters = 0.0
        if from + 1 <= to {
            for k in (from + 1)...to where k < seq.count {
                if let a = transit.stopsById[seq[k - 1]], let b = transit.stopsById[seq[k]] {
                    meters += TransitMotion.distanceMeters(LonLat(lon: a.lon, lat: a.lat), LonLat(lon: b.lon, lat: b.lat)) * Self.detour
                }
            }
        }
        return meters > 0 ? meters / Self.rideMetersPerSecond / 60 : Double(to - from) * Self.stopMinutes
    }

    private func terminus(_ line: String, _ dir: String) -> String {
        sequence[key(line, dir)]?.last.flatMap { transit.stopsById[$0]?.name } ?? line
    }

    public func plan(from origin: LonLat, to destination: LonLat, maxWalk: Double = JourneyPlanner.maxWalkMeters) async -> [JourneyOption] {
        let originStops = stopsNear(origin, maxWalk: maxWalk)
        let destStops = stopsNear(destination, maxWalk: maxWalk)
        let destLines = Set(destStops.flatMap { linesAt($0.id) })
        var options: [JourneyOption] = []
        var waitCache: [String: Int?] = [:]
        var walkCache: [Int: (meters: Double, seconds: Double)] = [:]

        func wait(_ stopId: Int, _ line: String) async -> Int {
            let cacheKey = "\(stopId):\(line)"
            if let cached = waitCache[cacheKey] { return cached ?? Self.defaultWait }
            let value = await nextBus(stopId, line)
            waitCache[cacheKey] = value
            return value ?? Self.defaultWait
        }

        func walkToDestination(_ stop: Stop) async -> (meters: Double, seconds: Double) {
            if let cached = walkCache[stop.id] { return cached }
            let value = await streetWalk(LonLat(lon: stop.lon, lat: stop.lat), destination)
            walkCache[stop.id] = value
            return value
        }

        for originStop in originStops {
            let walkO = await streetWalk(origin, LonLat(lon: originStop.lon, lat: originStop.lat))
            if walkO.meters > maxWalk { continue }
            let walkOMinutes = walkO.seconds / 60
            let firstLeg = JourneyLeg.walking(minutes: max(1, Int(walkOMinutes.rounded())), meters: Int(walkO.meters.rounded()),
                                              to: originStop.name)

            for line in linesAt(originStop.id).sorted() {
                for dir in ["ida", "vuelta"] {
                    guard let i = position[key(line, dir)]?[String(originStop.id)] else { continue }

                    // --- direct ride ---
                    for destStop in destStops where destStop.lines.contains(line) {
                        guard let j = position[key(line, dir)]?[String(destStop.id)], j > i else { continue }
                        let walkD = await walkToDestination(destStop)
                        if walkD.meters > maxWalk { continue }
                        let rideMinutes = ride(line, dir, from: i, to: j)
                        let waitMinutes = await wait(originStop.id, line)
                        let total = walkOMinutes + Double(waitMinutes) + rideMinutes + walkD.seconds / 60
                        options.append(JourneyOption(
                            totalMinutes: Int(total.rounded()),
                            walkMeters: Int((walkO.meters + walkD.meters).rounded()),
                            transfers: 0,
                            legs: [
                                firstLeg,
                                JourneyLeg(walk: false, minutes: max(1, Int(rideMinutes.rounded())), meters: 0, line: line,
                                           direction: dir, towards: terminus(line, dir), boardStop: originStop.name,
                                           alightStop: destStop.name, stops: j - i, waitMinutes: waitMinutes,
                                           boardStopId: originStop.id, alightStopId: destStop.id),
                                .walking(minutes: max(1, Int((walkD.seconds / 60).rounded())), meters: Int(walkD.meters.rounded()),
                                         to: "destination"),
                            ]
                        ))
                    }

                    // --- one transfer ---
                    let seq = sequence[key(line, dir)] ?? []
                    let last = min(i + Self.maxRideStops, seq.count - 1)
                    guard i + 1 <= last else { continue }
                    for k in (i + 1)...last {
                        guard let transfer = transit.stopsById[seq[k]], transfer.id != originStop.id else { continue }
                        for line2 in linesAt(transfer.id).subtracting([line]).sorted() where destLines.contains(line2) {
                            for dir2 in ["ida", "vuelta"] {
                                guard let ix = position[key(line2, dir2)]?[String(transfer.id)] else { continue }
                                for destStop in destStops where destStop.lines.contains(line2) {
                                    guard let j2 = position[key(line2, dir2)]?[String(destStop.id)], j2 > ix else { continue }
                                    let walkD = await walkToDestination(destStop)
                                    if walkD.meters > maxWalk { continue }
                                    let ride1 = ride(line, dir, from: i, to: k)
                                    let ride2 = ride(line2, dir2, from: ix, to: j2)
                                    let wait1 = await wait(originStop.id, line)
                                    let wait2 = await wait(transfer.id, line2)
                                    let total = walkOMinutes + Double(wait1) + ride1 + Self.transferPenalty
                                        + Double(wait2) + ride2 + walkD.seconds / 60
                                    options.append(JourneyOption(
                                        totalMinutes: Int(total.rounded()),
                                        walkMeters: Int((walkO.meters + walkD.meters).rounded()),
                                        transfers: 1,
                                        legs: [
                                            firstLeg,
                                            JourneyLeg(walk: false, minutes: max(1, Int(ride1.rounded())), meters: 0, line: line,
                                                       direction: dir, towards: terminus(line, dir), boardStop: originStop.name,
                                                       alightStop: transfer.name, stops: k - i, waitMinutes: wait1,
                                                       boardStopId: originStop.id, alightStopId: transfer.id),
                                            JourneyLeg(walk: false, minutes: max(1, Int(ride2.rounded())), meters: 0, line: line2,
                                                       direction: dir2, towards: terminus(line2, dir2), boardStop: transfer.name,
                                                       alightStop: destStop.name, stops: j2 - ix, waitMinutes: wait2,
                                                       boardStopId: transfer.id, alightStopId: destStop.id),
                                            .walking(minutes: max(1, Int((walkD.seconds / 60).rounded())),
                                                     meters: Int(walkD.meters.rounded()), to: "destination"),
                                        ]
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }

        var seen = Set<String>()
        let ranked = options.sorted { $0.totalMinutes < $1.totalMinutes }.filter { option in
            let signature = option.legs.filter { !$0.walk }.map { "\($0.line ?? ""):\($0.boardStop ?? "")" }.joined(separator: "|")
            return seen.insert(signature).inserted
        }
        // If a direct ride is at least as fast, transfer options are noise.
        let fastestDirect = ranked.filter { $0.transfers == 0 }.map(\.totalMinutes).min()
        let useful = fastestDirect.map { fastest in ranked.filter { $0.transfers == 0 || $0.totalMinutes < fastest } } ?? ranked
        return Array(useful.prefix(Self.maxOptions))
    }
}

extension EmtClient {
    /// (metres, seconds) walking on OSM streets (FOSSGIS OSRM); straight line
    /// × 1.25 at 1 m/s when the service fails, like Android's `walkMetrics`.
    public static func walkMetrics(_ a: LonLat, _ b: LonLat) async -> (meters: Double, seconds: Double) {
        let url = URL(string: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/\(a.lon),\(a.lat);\(b.lon),\(b.lat)?overview=false")!
        if let text = try? await HTTP.get(url, headers: ["User-Agent": webUserAgent]),
           let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
           let route = (root["routes"] as? [[String: Any]])?.first,
           let meters = jsonDouble(route["distance"]), let seconds = jsonDouble(route["duration"]) {
            return (meters, seconds)
        }
        let straight = TransitMotion.distanceMeters(a, b) * 1.25
        return (straight, straight / 1.25)
    }
}
