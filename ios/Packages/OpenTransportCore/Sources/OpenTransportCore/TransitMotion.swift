import Foundation

// Port of TransitMotion.kt.

public struct PreparedRoute: Sendable {
    public let points: [LonLat]
    public let cumulativeMeters: [Double]
    public var totalMeters: Double { cumulativeMeters.last ?? 0 }
}

public struct Projection: Sendable {
    public let distanceAlong: Double
    public let distanceFrom: Double
}

public struct StopHold: Sendable {
    public let id: String
    public let distanceAlong: Double
}

public struct UpcomingStop: Sendable {
    public let stop: Stop
    public let minutes: Int
}

public enum TransitMotion {
    private static let earthM = 6_371_000.0
    private static let metersPerDegree = 111_320.0
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }

    public static func distanceMeters(_ a: LonLat, _ b: LonLat) -> Double {
        let dLat = rad(b.lat - a.lat)
        let dLon = rad(b.lon - a.lon)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLon / 2), 2)
        return 2 * earthM * asin(sqrt(min(max(h, 0), 1)))
    }

    public static func prepare(_ points: [LonLat]) -> PreparedRoute {
        var cumulative = [Double](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() {
            cumulative[i] = cumulative[i - 1] + distanceMeters(points[i - 1], points[i])
        }
        return PreparedRoute(points: points, cumulativeMeters: cumulative)
    }

    public static func project(_ route: PreparedRoute, _ p: LonLat) -> Projection {
        guard route.points.count >= 2 else { return Projection(distanceAlong: 0, distanceFrom: .infinity) }
        let mLon = metersPerDegree * max(cos(rad(p.lat)), 1e-6)
        var bestS = 0.0
        var bestD = Double.infinity
        for i in 1..<route.points.count {
            let a = route.points[i - 1]
            let b = route.points[i]
            let ax = (a.lon - p.lon) * mLon
            let ay = (a.lat - p.lat) * metersPerDegree
            let bx = (b.lon - p.lon) * mLon
            let by = (b.lat - p.lat) * metersPerDegree
            let dx = bx - ax
            let dy = by - ay
            let denom = dx * dx + dy * dy
            let t = denom == 0 ? 0 : min(max(-(ax * dx + ay * dy) / denom, 0), 1)
            let d = hypot(ax + dx * t, ay + dy * t)
            if d < bestD {
                bestD = d
                bestS = route.cumulativeMeters[i - 1] + distanceMeters(a, b) * t
            }
        }
        return Projection(distanceAlong: bestS, distanceFrom: bestD)
    }

    public static func pointAt(_ route: PreparedRoute, _ s: Double) -> LonLat {
        guard let first = route.points.first else { return LonLat(lon: 0, lat: 0) }
        if route.points.count == 1 { return first }
        let value = min(max(s, 0), route.totalMeters)
        var lo = 0
        var hi = route.cumulativeMeters.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if route.cumulativeMeters[mid] <= value { lo = mid } else { hi = mid }
        }
        let segment = route.cumulativeMeters[hi] - route.cumulativeMeters[lo]
        let t = segment == 0 ? 0 : (value - route.cumulativeMeters[lo]) / segment
        let a = route.points[lo]
        let b = route.points[hi]
        return LonLat(lon: a.lon + (b.lon - a.lon) * t, lat: a.lat + (b.lat - a.lat) * t)
    }

    public static func clampSpeed(_ mps: Double, max limit: Double = 15) -> Double {
        mps < 0.3 ? 0 : min(mps, limit)
    }

    public static func predictArc(_ s: Double, speed: Double, seconds: Double, total: Double) -> Double {
        min(max(s + speed * seconds, 0), total)
    }

    public static func bearing(_ route: PreparedRoute, _ s: Double) -> Double {
        let step = 15.0
        var a = pointAt(route, s)
        var b = pointAt(route, min(route.totalMeters, s + step))
        if s + step > route.totalMeters {
            a = pointAt(route, max(0, s - step))
            b = pointAt(route, s)
        }
        let dx = (b.lon - a.lon) * cos(rad(a.lat))
        let dy = b.lat - a.lat
        return (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func itinerary(_ routes: [String: BusRoute], line: String, direction: String) -> [String] {
        guard let route = routes[line] else { return [] }
        return direction == "ida" ? route.ida.stops : route.vuelta.stops
    }

    public static func direction(_ routes: [String: BusRoute], line: String, last: Int, next: Int) -> String? {
        let l = String(last)
        let n = String(next)
        for exact in [true, false] {
            for dir in ["ida", "vuelta"] {
                let seq = itinerary(routes, line: line, direction: dir)
                guard let ni = seq.firstIndex(of: n) else { continue }
                if !exact { return dir }
                if let li = seq.firstIndex(of: l), ni == li + 1 { return dir }
            }
        }
        return nil
    }

    public static func stopHold(_ hold: StopHold?, s: Double, next: String, stopS: Double?) -> StopHold? {
        if let hold {
            let left = s > hold.distanceAlong + 30 || (next != hold.id && s > hold.distanceAlong - 10)
            return left ? nil : hold
        }
        if let stopS, abs(s - stopS) <= 35 { return StopHold(id: next, distanceAlong: stopS) }
        return nil
    }

    public static func upcoming(
        _ routes: [String: BusRoute],
        stopsById: [String: Stop],
        line: String,
        dir: String,
        next: Int,
        position: LonLat,
        limit: Int = 12
    ) -> [UpcomingStop] {
        let seq = itinerary(routes, line: line, direction: dir)
        guard let first = seq.firstIndex(of: String(next)) else { return [] }
        var prev = position
        var distance = 0.0
        return seq[first...].prefix(limit).compactMap { id in
            guard let stop = stopsById[id] else { return nil }
            let pos = LonLat(lon: stop.lon, lat: stop.lat)
            distance += distanceMeters(prev, pos)
            prev = pos
            return UpcomingStop(stop: stop, minutes: Swift.max(1, Int((distance / 1000 / 18 * 60).rounded())))
        }
    }

    public static func formatDistance(_ meters: Double) -> String {
        if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), meters / 1000)
    }
}
