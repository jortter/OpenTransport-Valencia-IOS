import Foundation

/// Texts that only the iOS app needs (not present in Language.kt).
extension Strings {
    public var arrivals: String { pick("Llegadas", "Arrivals", "Arribades") }
    public var loading: String { pick("Cargando…", "Loading…", "Carregant…") }
    public var comingSoon: String { pick("Próximamente en iOS", "Coming soon on iOS", "Pròximament en iOS") }
    public var stopCode: String { pick("Parada", "Stop", "Parada") }
    public var refresh: String { pick("Actualizar", "Refresh", "Actualitzar") }

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
