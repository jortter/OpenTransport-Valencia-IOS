import Foundation

/// Texts that only the iOS app needs (not present in Language.kt).
extension Strings {
    public var arrivals: String { pick("Llegadas", "Arrivals", "Arribades") }
    public var loading: String { pick("Cargando…", "Loading…", "Carregant…") }
    public var comingSoon: String { pick("Próximamente en iOS", "Coming soon on iOS", "Pròximament en iOS") }
    public var stopCode: String { pick("Parada", "Stop", "Parada") }
    public var refresh: String { pick("Actualizar", "Refresh", "Actualitzar") }

    public func busTitle(_ number: Int) -> String { pick("Autobús \(number)", "Bus \(number)", "Autobús \(number)") }
    public var nextStops: String { pick("Próximas paradas", "Next stops", "Pròximes parades") }
    public var view3D: String { pick("Vista 3D", "3D view", "Vista 3D") }

    public var mechanicalBikes: String { pick("Mecánicas", "Mechanical", "Mecàniques") }
    public var electricBikes: String { pick("Eléctricas", "Electric", "Elèctriques") }
    public func bikeTitle(_ number: Int) -> String { pick("Bici \(number)", "Bike \(number)", "Bici \(number)") }
    public func standTitle(_ number: Int) -> String { pick("Anclaje \(number)", "Stand \(number)", "Ancoratge \(number)") }

    public func lineTitle(_ line: String) -> String { pick("Línea \(line)", "Line \(line)", "Línia \(line)") }

    public func liveBuses(_ count: Int) -> String {
        count == 1
            ? pick("1 autobús en directo", "1 bus live", "1 autobús en directe")
            : pick("\(count) autobuses en directo", "\(count) buses live", "\(count) autobusos en directe")
    }

    /// EMT's "ida"/"vuelta" (outbound/return).
    public func directionLabel(_ direction: String) -> String {
        direction == "vuelta" ? pick("vuelta", "return", "tornada") : pick("ida", "outbound", "anada")
    }
}
