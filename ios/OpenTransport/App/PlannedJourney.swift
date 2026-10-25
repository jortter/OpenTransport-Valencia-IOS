import Foundation
import OpenTransportCore

/// A chosen trip drawn on the map: rides along their line shapes, walks as
/// straight dashed stretches, and a dot at each boarding/alighting point
/// (port of `journeySegments` / `legShape` in EmtApp.kt).
struct PlannedJourney: Equatable {
    struct Segment: Equatable {
        let walk: Bool
        let points: [LonLat]
        let colorIndex: Int
    }

    struct Dot: Equatable {
        let point: LonLat
        let colorIndex: Int
    }

    let id = UUID()
    let option: JourneyOption
    let segments: [Segment]
    let dots: [Dot]
    let stopIds: Set<Int>

    init(option: JourneyOption, transit: TransitData, origin: LonLat?, destination: LonLat?) {
        self.option = option
        let rides = option.legs.filter { !$0.walk }
        var segments: [Segment] = []
        var dots: [String: Dot] = [:]
        var dotOrder: [String] = []
        func dot(_ point: LonLat, _ colorIndex: Int) {
            // A transfer is drawn once, in the colour of the ride it starts.
            let key = "\(Int((point.lat * 1e5).rounded())),\(Int((point.lon * 1e5).rounded()))"
            if dots[key] == nil { dotOrder.append(key) }
            dots[key] = Dot(point: point, colorIndex: colorIndex)
        }
        func stop(_ id: Int?) -> Stop? { id.flatMap { transit.stopsById[String($0)] } }

        if let origin, let board = stop(rides.first?.boardStopId) {
            segments.append(Segment(walk: true, points: [origin, LonLat(lon: board.lon, lat: board.lat)], colorIndex: 0))
        }
        for (index, leg) in rides.enumerated() {
            guard let line = leg.line, let route = transit.routes[line],
                  let board = stop(leg.boardStopId), let alight = stop(leg.alightStopId) else { continue }
            // A change on foot to a nearby stop of another network.
            if index > 0, let previous = stop(rides[index - 1].alightStopId), previous.id != board.id {
                segments.append(Segment(walk: true, points: [LonLat(lon: previous.lon, lat: previous.lat),
                                                             LonLat(lon: board.lon, lat: board.lat)], colorIndex: 0))
            }
            let points = Self.legShape(route, direction: leg.direction, board: board, alight: alight)
            if points.count >= 2 { segments.append(Segment(walk: false, points: points, colorIndex: index)) }
            dot(LonLat(lon: board.lon, lat: board.lat), index)
            dot(LonLat(lon: alight.lon, lat: alight.lat), index)
        }
        if let destination, let alight = stop(rides.last?.alightStopId) {
            segments.append(Segment(walk: true, points: [LonLat(lon: alight.lon, lat: alight.lat), destination], colorIndex: 0))
        }
        self.segments = segments
        self.dots = dotOrder.compactMap { dots[$0] }
        self.stopIds = Set(rides.flatMap { [$0.boardStopId, $0.alightStopId].compactMap { $0 } })
    }

    var bounds: LngLatBounds? {
        let points = segments.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        return LngLatBounds(west: points.map(\.lon).min()!, south: points.map(\.lat).min()!,
                            east: points.map(\.lon).max()!, north: points.map(\.lat).max()!)
    }

    /// The stretch of an itinerary's shape between two stops, in travel order.
    static func legShape(_ route: BusRoute, direction: String?, board: Stop, alight: Stop) -> [LonLat] {
        func squared(_ point: LonLat, _ stop: Stop) -> Double {
            let dx = point.lon - stop.lon
            let dy = point.lat - stop.lat
            return dx * dx + dy * dy
        }
        func nearest(_ shape: [LonLat], _ stop: Stop) -> Int {
            shape.indices.min { squared(shape[$0], stop) < squared(shape[$1], stop) } ?? 0
        }
        var best: [LonLat] = []
        var bestScore = Double.greatestFiniteMagnitude
        for shape in direction == "vuelta" ? route.vuelta.shapes : route.ida.shapes where shape.count >= 2 {
            let from = nearest(shape, board)
            let to = nearest(shape, alight)
            let score = squared(shape[from], board) + squared(shape[to], alight)
            if score < bestScore {
                bestScore = score
                best = from <= to ? Array(shape[from...to]) : Array(shape[to...from].reversed())
            }
        }
        return best
    }

    static func == (a: PlannedJourney, b: PlannedJourney) -> Bool { a.id == b.id }
}
