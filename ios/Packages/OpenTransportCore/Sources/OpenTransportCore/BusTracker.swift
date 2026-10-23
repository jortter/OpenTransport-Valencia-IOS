import Foundation

/// A live bus as drawn on the map. Reference type, mutated in place every
/// frame (same as Android's `BusPosition`).
public final class BusPosition: @unchecked Sendable {
    public let number: Int
    public let line: String
    public let destination: String
    public internal(set) var nextStop: Int
    public internal(set) var direction: String?
    public internal(set) var timestamp: String
    var observed: LonLat
    var observedAt: Date
    var velocity: LonLat
    public internal(set) var render: LonLat
    public internal(set) var route: PreparedRoute?
    var routeKey: String?
    var routeS: Double
    var observedS: Double
    var speedMps: Double
    var hold: StopHold?
    public internal(set) var bearing: Double = 0

    init(fix: BusFix, now: Date, candidate: (String, PreparedRoute, Projection)?) {
        number = fix.number
        line = fix.line
        destination = fix.destination
        nextStop = fix.nextStop
        direction = fix.direction
        timestamp = fix.timestamp
        let position = LonLat(lon: fix.lon, lat: fix.lat)
        observed = position
        observedAt = now
        velocity = LonLat(lon: 0, lat: 0)
        speedMps = 0
        if let candidate, candidate.2.distanceFrom <= BusTracker.maxOffRoute {
            route = candidate.1
            routeKey = candidate.0
            routeS = candidate.2.distanceAlong
            observedS = candidate.2.distanceAlong
            render = TransitMotion.pointAt(candidate.1, candidate.2.distanceAlong)
        } else {
            render = position
            routeS = 0
            observedS = 0
        }
    }
}

/// Port of `merge`, `advance` and `nearestRoute` in EmtApp.kt: turns the
/// sparse GPS fixes from EMT into smooth positions snapped to the route.
public final class BusTracker: @unchecked Sendable {
    static let maxOffRoute = 150.0

    private let transit: TransitData
    private var prepared: [String: PreparedRoute] = [:]
    public private(set) var buses: [BusPosition] = []

    public init(transit: TransitData) {
        self.transit = transit
    }

    public func clear() {
        buses = []
    }

    public func merge(_ fixes: [BusFix], now: Date = Date()) {
        var byNumber: [Int: BusPosition] = [:]
        for bus in buses { byNumber[bus.number] = bus }
        var result: [BusPosition] = []
        var seen = Set<Int>()

        for fix in fixes where !seen.contains(fix.number) {
            seen.insert(fix.number)
            let position = LonLat(lon: fix.lon, lat: fix.lat)
            guard let current = byNumber[fix.number] else {
                result.append(BusPosition(fix: fix, now: now, candidate: nearestRoute(fix.line, fix.direction, position)))
                continue
            }
            let fresh = fix.timestamp != current.timestamp
            let moved = abs(position.lon - current.observed.lon) > 1e-6 || abs(position.lat - current.observed.lat) > 1e-6
            if fresh {
                if moved {
                    let seconds = Self.secondsBetween(current.timestamp, fix.timestamp)
                    if let candidate = nearestRoute(fix.line, fix.direction, position),
                       candidate.2.distanceFrom <= Self.maxOffRoute {
                        let (key, route, projection) = candidate
                        if current.route == nil || current.routeKey != key {
                            current.route = route
                            current.routeKey = key
                            current.routeS = projection.distanceAlong
                            current.observedS = projection.distanceAlong
                        } else {
                            if seconds > 0.5 {
                                let speed = TransitMotion.clampSpeed((projection.distanceAlong - current.observedS) / seconds)
                                current.speedMps = (current.speedMps + speed) / 2
                            }
                            current.observedS = projection.distanceAlong
                        }
                    } else {
                        current.route = nil
                        current.routeKey = nil
                        if seconds > 0.5 {
                            current.velocity = LonLat(lon: (position.lon - current.observed.lon) / seconds,
                                                      lat: (position.lat - current.observed.lat) / seconds)
                        }
                    }
                    current.observed = position
                    current.observedAt = now
                } else {
                    current.speedMps *= 0.5
                    current.observedAt = now
                }
                current.timestamp = fix.timestamp
                current.nextStop = fix.nextStop
                current.direction = fix.direction
                if let route = current.route {
                    let stop = transit.stopsById[String(fix.nextStop)]
                    let stopS = stop.map { TransitMotion.project(route, LonLat(lon: $0.lon, lat: $0.lat)).distanceAlong }
                    current.hold = TransitMotion.stopHold(current.hold, s: current.observedS, next: String(fix.nextStop), stopS: stopS)
                }
            }
            result.append(current)
        }
        buses = result
    }

    /// Moves every bus one animation frame towards its predicted position.
    public func advance(now: Date = Date()) {
        let k = 1 - exp(-16.0 / 400.0)
        for bus in buses {
            if let route = bus.route {
                let age = now.timeIntervalSince(bus.observedAt)
                let speed = age > 25 ? 0 : bus.speedMps
                let target = bus.hold?.distanceAlong
                    ?? TransitMotion.predictArc(bus.observedS, speed: speed, seconds: age, total: route.totalMeters)
                let kk = abs(target - bus.routeS) > 25 ? 1 - exp(-16.0 / 2500.0) : k
                bus.routeS += (target - bus.routeS) * kk
                bus.render = TransitMotion.pointAt(route, bus.routeS)
                bus.bearing = TransitMotion.bearing(route, bus.routeS)
            } else {
                let seconds = now.timeIntervalSince(bus.observedAt)
                let px = bus.observed.lon + bus.velocity.lon * seconds
                let py = bus.observed.lat + bus.velocity.lat * seconds
                let kk = 1 - exp(-16.0 / 2500.0)
                bus.render = LonLat(lon: bus.render.lon + (px - bus.render.lon) * kk,
                                    lat: bus.render.lat + (py - bus.render.lat) * kk)
            }
        }
    }

    private func nearestRoute(_ line: String, _ direction: String?, _ position: LonLat) -> (String, PreparedRoute, Projection)? {
        guard let direction, let route = transit.routes[line] else { return nil }
        let shapes = direction == "ida" ? route.ida.shapes : route.vuelta.shapes
        var best: (String, PreparedRoute, Projection)?
        for (index, shape) in shapes.enumerated() {
            let key = "\(line)|\(direction)|\(index)"
            let preparedRoute = prepared[key] ?? TransitMotion.prepare(shape)
            prepared[key] = preparedRoute
            let projection = TransitMotion.project(preparedRoute, position)
            if best == nil || projection.distanceFrom < best!.2.distanceFrom { best = (key, preparedRoute, projection) }
        }
        return best
    }

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Madrid")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func secondsBetween(_ from: String, _ to: String) -> Double {
        guard let a = timeFormat.date(from: from), let b = timeFormat.date(from: to) else { return 0 }
        return b.timeIntervalSince(a)
    }
}

extension BusRoute {
    /// Bounds of both directions (Android's `lineBounds`).
    public var bounds: LngLatBounds? {
        let points = (ida.shapes + vuelta.shapes).flatMap { $0 }
        guard !points.isEmpty else { return nil }
        return LngLatBounds(west: points.map(\.lon).min()!, south: points.map(\.lat).min()!,
                            east: points.map(\.lon).max()!, north: points.map(\.lat).max()!)
    }
}
