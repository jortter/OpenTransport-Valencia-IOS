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
    /// Stops within a short walk of each stop (other networks included), for
    /// changes between stops that are not the same one: an EMT stop and the
    /// Metro or Metrobús stop across the street.
    private var neighbours: [Int: [(stop: Stop, meters: Double)]] = [:]

    static let detour = 1.25
    static let rideMetersPerSecond = 5.0
    static let stopMinutes = 1.6
    public static let maxWalkMeters = 1000.0
    static let maxRideStops = 30
    static let transferPenalty = 3.0
    /// Longest straight-line walk between two stops to change lines.
    static let maxTransferWalk = 300.0
    static let defaultWait = 6
    static let maxWait = 180
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
        neighbours = Self.neighbours(of: transit.stops, within: Self.maxTransferWalk)
    }

    /// EMT (0), Metro (1) or Metrobús (2), from the id ranges the loaders use.
    static func network(_ stopId: Int) -> Int { stopId / TransitDataLoader.metroIdBase }

    /// Stops within `meters` of each other, found through a coarse grid so it
    /// stays linear in the number of stops.
    static func neighbours(of stops: [Stop], within meters: Double) -> [Int: [(stop: Stop, meters: Double)]] {
        let cell = 0.004 // ≈ 440 m of latitude, larger than `meters`
        func key(_ lat: Double, _ lon: Double) -> String { "\(Int((lat / cell).rounded(.down))):\(Int((lon / cell).rounded(.down)))" }
        var grid: [String: [Stop]] = [:]
        for stop in stops { grid[key(stop.lat, stop.lon), default: []].append(stop) }
        var out: [Int: [(stop: Stop, meters: Double)]] = [:]
        for stop in stops {
            let row = Int((stop.lat / cell).rounded(.down)), column = Int((stop.lon / cell).rounded(.down))
            var near: [(stop: Stop, meters: Double)] = []
            for dr in -1...1 {
                for dc in -1...1 {
                    // Only other networks: changing between EMT lines happens at a shared stop,
                    // and every EMT stop nearby would multiply the search in the centre.
                    for other in grid["\(row + dr):\(column + dc)"] ?? [] where Self.network(other.id) != Self.network(stop.id) {
                        let d = TransitMotion.distanceMeters(LonLat(lon: stop.lon, lat: stop.lat), LonLat(lon: other.lon, lat: other.lat))
                        if d <= meters { near.append((other, d)) }
                    }
                }
            }
            if !near.isEmpty { out[stop.id] = Array(near.sorted { $0.meters < $1.meters }.prefix(4)) }
        }
        return out
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

    private typealias Walk = (meters: Double, seconds: Double)

    /// One bus ride of a candidate trip.
    private struct Ride {
        let line: String
        let dir: String
        let board: Stop
        let alight: Stop
        let stops: Int
        let minutes: Double
    }

    /// A trip before live waits are known.
    private struct Candidate {
        let origin: Stop
        let destination: Stop
        let rides: [Ride]
        /// Metres walked between the two rides (0 when changing at the same stop).
        var transferWalk = 0.0

        var signature: String { rides.map { "\($0.line):\($0.board.name)" }.joined(separator: "|") }
    }

    /// Minutes to walk a straight-line distance between two stops (street
    /// detour at 1 m/s, as in the walking fallback).
    static func walkMinutes(_ meters: Double) -> Double { meters * detour / 60 }

    /// Walks to (or from) several stops at once.
    private func walks(_ stops: [Stop], _ walk: @escaping @Sendable (Stop) async -> Walk) async -> [Int: Walk] {
        await withTaskGroup(of: (Int, Walk).self) { group in
            for stop in stops { group.addTask { (stop.id, await walk(stop)) } }
            var out: [Int: Walk] = [:]
            for await (id, value) in group { out[id] = value }
            return out
        }
    }

    /// Plans in three steps so it stays fast: the street walks in parallel,
    /// then every direct / one-transfer ride offline, then live waits only for
    /// the best few candidates (again in parallel). Asking for every wait one
    /// by one took minutes.
    public func plan(from origin: LonLat, to destination: LonLat, maxWalk: Double = JourneyPlanner.maxWalkMeters) async -> [JourneyOption] {
        let originStops = stopsNear(origin, maxWalk: maxWalk)
        let destStops = stopsNear(destination, maxWalk: maxWalk)
        let destLines = Set(destStops.flatMap { linesAt($0.id) })
        let streetWalk = self.streetWalk

        async let originWalks = walks(originStops) { await streetWalk(origin, LonLat(lon: $0.lon, lat: $0.lat)) }
        async let destWalks = walks(destStops) { await streetWalk(LonLat(lon: $0.lon, lat: $0.lat), destination) }
        let walkO = (await originWalks).filter { $0.value.meters <= maxWalk }
        let walkD = (await destWalks).filter { $0.value.meters <= maxWalk }

        var candidates: [Candidate] = []
        for originStop in originStops where walkO[originStop.id] != nil {
            for line in linesAt(originStop.id).sorted() {
                for dir in ["ida", "vuelta"] {
                    guard let i = position[key(line, dir)]?[String(originStop.id)] else { continue }

                    // --- direct ride ---
                    for destStop in destStops where walkD[destStop.id] != nil && destStop.lines.contains(line) {
                        guard let j = position[key(line, dir)]?[String(destStop.id)], j > i else { continue }
                        let ride = Ride(line: line, dir: dir, board: originStop, alight: destStop, stops: j - i,
                                        minutes: self.ride(line, dir, from: i, to: j))
                        candidates.append(Candidate(origin: originStop, destination: destStop, rides: [ride]))
                    }

                    // --- one transfer ---
                    let seq = sequence[key(line, dir)] ?? []
                    let last = min(i + Self.maxRideStops, seq.count - 1)
                    guard i + 1 <= last else { continue }
                    for k in (i + 1)...last {
                        guard let transfer = transit.stopsById[seq[k]], transfer.id != originStop.id else { continue }
                        // Change at this stop, or walk to a nearby one (another network's).
                        for (board2, walk) in [(transfer, 0.0)] + (neighbours[transfer.id] ?? []) {
                            for line2 in linesAt(board2.id).subtracting([line]).sorted() where destLines.contains(line2) {
                                for dir2 in ["ida", "vuelta"] {
                                    guard let ix = position[key(line2, dir2)]?[String(board2.id)] else { continue }
                                    for destStop in destStops where walkD[destStop.id] != nil && destStop.lines.contains(line2) {
                                        guard let j2 = position[key(line2, dir2)]?[String(destStop.id)], j2 > ix else { continue }
                                        let first = Ride(line: line, dir: dir, board: originStop, alight: transfer, stops: k - i,
                                                         minutes: self.ride(line, dir, from: i, to: k))
                                        let second = Ride(line: line2, dir: dir2, board: board2, alight: destStop, stops: j2 - ix,
                                                          minutes: self.ride(line2, dir2, from: ix, to: j2))
                                        candidates.append(Candidate(origin: originStop, destination: destStop, rides: [first, second],
                                                                    transferWalk: walk))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        func total(_ c: Candidate, wait: (Ride) -> Int) -> Double {
            guard let o = walkO[c.origin.id], let d = walkD[c.destination.id] else { return .infinity }
            return o.seconds / 60 + d.seconds / 60 + Double(c.rides.count - 1) * Self.transferPenalty
                + Self.walkMinutes(c.transferWalk) + c.rides.reduce(0) { $0 + Double(wait($1)) + $1.minutes }
        }

        // Best few by the default wait, one per signature.
        var seenSignatures = Set<String>()
        let shortlist = candidates
            .map { ($0, total($0) { _ in Self.defaultWait }) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { seenSignatures.insert($0.signature).inserted }
            .prefix(Self.maxOptions * 3)

        // Live waits for just those rides, in parallel.
        let nextBus = self.nextBus
        let pairs = Set(shortlist.flatMap { $0.rides.map { "\($0.board.id):\($0.line)" } })
        let waits: [String: Int] = await withTaskGroup(of: (String, Int?).self) { group in
            for pair in pairs {
                let parts = pair.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, let stop = Int(parts[0]) else { continue }
                let line = String(parts[1])
                group.addTask { (pair, await nextBus(stop, line)) }
            }
            var out: [String: Int] = [:]
            // An unknown or absurd wait (e.g. Int.max for "no estimate") would
            // overflow the trip time: use the default instead.
            for await (pair, value) in group { out[pair] = value.flatMap { (0...Self.maxWait).contains($0) ? $0 : nil } ?? Self.defaultWait }
            return out
        }
        func wait(_ ride: Ride) -> Int { waits["\(ride.board.id):\(ride.line)"] ?? Self.defaultWait }

        let options: [JourneyOption] = shortlist.compactMap { c in
            guard let o = walkO[c.origin.id], let d = walkD[c.destination.id] else { return nil }
            let minutes = total(c, wait: wait)
            guard minutes.isFinite else { return nil }
            var legs = [JourneyLeg.walking(minutes: max(1, Int((o.seconds / 60).rounded())), meters: Int(o.meters.rounded()),
                                           to: c.origin.name)]
            for (index, ride) in c.rides.enumerated() {
                if index > 0, c.transferWalk > 0 {
                    legs.append(.walking(minutes: max(1, Int(Self.walkMinutes(c.transferWalk).rounded())),
                                         meters: Int((c.transferWalk * Self.detour).rounded()), to: ride.board.name))
                }
                legs.append(JourneyLeg(walk: false, minutes: max(1, Int(ride.minutes.rounded())), meters: 0, line: ride.line,
                                       direction: ride.dir, towards: terminus(ride.line, ride.dir), boardStop: ride.board.name,
                                       alightStop: ride.alight.name, stops: ride.stops, waitMinutes: wait(ride),
                                       boardStopId: ride.board.id, alightStopId: ride.alight.id))
            }
            legs.append(.walking(minutes: max(1, Int((d.seconds / 60).rounded())), meters: Int(d.meters.rounded()), to: "destination"))
            return JourneyOption(totalMinutes: Int(minutes.rounded()),
                                 walkMeters: Int((o.meters + d.meters + c.transferWalk * Self.detour).rounded()),
                                 transfers: c.rides.count - 1, legs: legs)
        }

        // The same lines from a neighbouring stop is the same advice: keep the fastest.
        var seenLines = Set<String>()
        let ranked = options.sorted { $0.totalMinutes < $1.totalMinutes }.filter { option in
            seenLines.insert(option.legs.compactMap(\.line).joined(separator: ">")).inserted
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
