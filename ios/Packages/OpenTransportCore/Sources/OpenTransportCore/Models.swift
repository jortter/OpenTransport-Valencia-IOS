import Foundation

// Port of app/src/main/java/es/emtvalencia/live/TransitData.kt (and the value
// types of TransitMotion.kt). Names are kept 1:1 so Android changes are easy to
// carry over.

public struct LonLat: Hashable, Sendable {
    public var lon: Double
    public var lat: Double
    public init(lon: Double, lat: Double) {
        self.lon = lon
        self.lat = lat
    }
}

public struct Stop: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let lines: [String]
    public let lat: Double
    public let lon: Double
    public var metro: Bool

    public init(id: Int, name: String, lines: [String], lat: Double, lon: Double, metro: Bool = false) {
        self.id = id
        self.name = name
        self.lines = lines
        self.lat = lat
        self.lon = lon
        self.metro = metro
    }

    /// Name without the trailing "(123)" stop code.
    public var cleanName: String { cleanStopName(name) }
}

public func cleanStopName(_ nombre: String) -> String {
    nombre.replacingOccurrences(of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

public struct RouteDirection: Sendable {
    public let shapes: [[LonLat]]
    public let stops: [String]
    public init(shapes: [[LonLat]], stops: [String]) {
        self.shapes = shapes
        self.stops = stops
    }
}

public struct BusRoute: Sendable {
    public let ida: RouteDirection
    public let vuelta: RouteDirection
    public init(ida: RouteDirection, vuelta: RouteDirection) {
        self.ida = ida
        self.vuelta = vuelta
    }
}

public struct TransitData: Sendable {
    public let stops: [Stop]
    public let stopsById: [String: Stop]
    public let routes: [String: BusRoute]
    public init(stops: [Stop], stopsById: [String: Stop], routes: [String: BusRoute]) {
        self.stops = stops
        self.stopsById = stopsById
        self.routes = routes
    }
}

public struct BusFix: Hashable, Sendable {
    public let number: Int
    public let line: String
    public let destination: String
    public let lastStop: Int
    public let nextStop: Int
    public let lon: Double
    public let lat: Double
    public let timestamp: String
    public let direction: String?
}

public struct Arrival: Hashable, Sendable {
    public let line: String
    public let destination: String
    public let minutes: String
    public let arrivalTime: String
    public let source: String

    public init(line: String, destination: String, minutes: String, arrivalTime: String = "", source: String = "emt") {
        self.line = line
        self.destination = destination
        self.minutes = minutes
        self.arrivalTime = arrivalTime
        self.source = source
    }
}

public struct NearBus: Hashable, Sendable {
    public let line: String
    public let number: Int
    public let lat: Double
    public let lon: Double
    public let direction: String?
    public let minutes: Int
    public let distanceMeters: Double
}

public struct StopInfo: Sendable {
    public let stop: Stop
    public let arrivals: [Arrival]
    public let buses: [NearBus]
}

public struct Incident: Hashable, Sendable {
    public let title: String
    public let date: String
    public let lines: Set<String>
    public let network: Network
    public let detail: String
    public let url: String

    public init(title: String, date: String, lines: Set<String>, network: Network = .emt, detail: String = "", url: String = "") {
        self.title = title
        self.date = date
        self.lines = lines
        self.network = network
        self.detail = detail
        self.url = url
    }
}

/// The networks the app can draw on the map.
public enum Network: String, CaseIterable, Sendable {
    case emt = "Emt"
    case metro = "Metro"
    case valenbisi = "Valenbisi"
    case metrobus = "Metrobus"
    case rodalies = "Rodalies"

    public var label: String {
        switch self {
        case .emt: return "EMT"
        case .metro: return "Metro"
        case .valenbisi: return "Bici"
        case .metrobus: return "Metrobús"
        case .rodalies: return "Rodalies"
        }
    }

    /// Logo file name inside the bundled assets folder.
    public var asset: String {
        switch self {
        case .emt: return "emt.png"
        case .metro: return "metrovalencia.png"
        case .valenbisi: return "valenbisi.png"
        case .metrobus: return "metrobus.png"
        case .rodalies: return "rodalies.png"
        }
    }
}

/// A point of interest from any network, so the map can draw them uniformly.
public struct Place: Identifiable, Hashable, Sendable {
    public let id: String
    public let network: Network
    public let name: String
    public let lat: Double
    public let lon: Double
    public var lines: [String] = []
    public var detail: String = ""
    public var available: Int = -1
    public var free: Int = -1
    public var open: Bool = true
    public var mechanical: Int = -1
    public var electric: Int = -1
}

public struct LngLatBounds: Hashable, Sendable {
    public let west: Double
    public let south: Double
    public let east: Double
    public let north: Double

    public init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west
        self.south = south
        self.east = east
        self.north = north
    }
}
