import Foundation

/// Texts that only the iOS app needs (not present in Language.kt).
extension Strings {
    public var arrivals: String { pick("Llegadas", "Arrivals", "Arribades") }
    public var loading: String { pick("Cargando…", "Loading…", "Carregant…") }
    public var comingSoon: String { pick("Próximamente en iOS", "Coming soon on iOS", "Pròximament en iOS") }
    public var stopCode: String { pick("Parada", "Stop", "Parada") }
    public var refresh: String { pick("Actualizar", "Refresh", "Actualitzar") }
}
