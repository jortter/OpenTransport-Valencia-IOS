import Foundation

/// App language: Spanish, English or Valencian. Port of Language.kt.
public enum Language: String, CaseIterable, Identifiable, Sendable {
    case es, en, va

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        case .va: return "Valencià"
        }
    }

    public static func of(_ code: String?) -> Language { Language(rawValue: code ?? "") ?? .en }
}

/// Lightweight string table, generated from Language.kt (same keys and texts).
public struct Strings: Sendable {
    public let language: Language

    public init(_ language: Language) {
        self.language = language
    }

    func pick(_ es: String, _ en: String, _ va: String? = nil) -> String {
        switch language {
        case .es: return es
        case .en: return en
        case .va: return va ?? es
        }
    }

    public var map: String { pick("Mapa", "Map") }
    public var saved: String { pick("Guardadas", "Saved", "Guardades") }
    public var alerts: String { pick("Avisos", "Alerts", "Avisos") }
    public var plan: String { pick("Planificar", "Plan", "Planificar") }
    public var settings: String { pick("Ajustes", "Settings", "Ajustos") }
    public var languageTitle: String { pick("Idioma", "Language", "Idioma") }
    public var searchStop: String { pick("Buscar parada", "Search a stop", "Buscar parada") }
    public var searchLine: String { pick("Buscar línea", "Search a line", "Buscar línia") }
    public var stops: String { pick("Paradas", "Stops", "Parades") }
    public var lines: String { pick("Líneas", "Lines", "Línies") }
    public var planTitle: String { pick("Planifica un viaje", "Plan a trip", "Planifica un viatge") }
    public var layersTitle: String { pick("Mostrar en el mapa", "Show on the map", "Mostrar en el mapa") }
    public var nextDepartures: String { pick("Próximas salidas", "Next departures", "Pròximes eixides") }
    public var appName: String { "OpenTransport Valencia" }
    public var welcome: String { pick("Transporte público de València en tiempo real: EMT, Metrovalencia, Rodalies, Metrobús y Valenbisi en un solo mapa.", "Valencia public transport in real time: EMT buses, Metrovalencia, Rodalies, Metrobús and Valenbisi on one map.", "Transport públic de València en temps real: EMT, Metrovalencia, Rodalies, Metrobús i Valenbisi en un sol mapa.") }
    public var onboardFeatures: String { pick("Qué puedes hacer", "What you can do", "Què pots fer") }
    public var onboardMore: String { pick("Y además", "And more", "I a més") }
    public var previous: String { pick("Atrás", "Back", "Arrere") }
    public var next: String { pick("Siguiente", "Next", "Següent") }
    public var featureBus: String { pick("Ver autobuses EMT en directo sobre el mapa", "Track EMT buses live on the map", "Veure autobusos EMT en directe al mapa") }
    public var featureMetro: String { pick("Metro y tranvía con llegadas en tiempo real", "Metro & tram with live arrivals", "Metro i tramvia amb arribades en temps real") }
    public var featureRodalies: String { pick("Cercanías/Rodalies con horarios y avisos", "Rodalies trains with times and alerts", "Rodalies amb horaris i avisos") }
    public var featureBikes: String { pick("Bicis Valenbisi: bicis y anclajes libres", "Valenbisi bikes: available bikes and docks", "Bicis Valenbisi: bicis i ancoratges lliures") }
    public var featureFavs: String { pick("Guarda paradas y recibe avisos de llegada", "Save stops and get arrival alerts", "Guarda parades i rep avisos d'arribada") }
    public var featurePlan: String { pick("Planifica un viaje combinando líneas (beta)", "Plan a trip combining lines (beta)", "Planifica un viatge combinant línies (beta)") }
    public var featureAlerts: String { pick("Avisos e incidencias del servicio", "Service alerts and incidents", "Avisos i incidències del servei") }
    public var onboardMap: String { pick("Qué mostrar en el mapa", "What to show on the map", "Què mostrar al mapa") }
    public var mapStyle: String { pick("Estilo del mapa", "Map style", "Estil del mapa") }
    public var appearance: String { pick("Tema de la app", "App theme", "Tema de l'app") }
    public var auto: String { pick("Automático", "Auto", "Automàtic") }
    public var light: String { pick("Claro", "Light", "Clar") }
    public var dark: String { pick("Oscuro", "Dark", "Fosc") }
    public var start: String { pick("Empezar", "Get started", "Comença") }
    public var all: String { pick("Todas", "All", "Totes") }
    public var close: String { pick("Cerrar", "Close", "Tanca") }
    public var open: String { pick("Abierto", "Open", "Obert") }
    public var closed: String { pick("Cerrado", "Closed", "Tancat") }
    public var remove: String { pick("Quitar", "Remove", "Lleva") }
    public var favourite: String { pick("Favorito", "Favourite", "Favorit") }
    public var addFavourite: String { pick("Añadir a favoritos", "Add favourite", "Afegir a favorits") }
    public var removeFavourite: String { pick("Quitar de favoritos", "Remove favourite", "Llevar de favorits") }
    public var hide: String { pick("Ocultar", "Hide", "Amaga") }
    public var show: String { pick("Mostrar", "Show", "Mostra") }
    public var noMatches: String { pick("Sin resultados", "No matches", "Sense resultats") }
    public var typeToSearch: String { pick("Escribe para buscar", "Type to search", "Escriu per a buscar") }
    public var mapLayers: String { pick("Capas del mapa", "Map layers", "Capes del mapa") }
    public var myLocation: String { pick("Mi ubicación", "My location", "La meua ubicació") }
    public var resetView: String { pick("Restablecer vista", "Reset view", "Restablir vista") }
    public var timetable: String { pick("Horarios", "Timetable", "Horaris") }
    public var trip: String { pick("Viaje", "Trip", "Viatge") }
    public var bikes: String { pick("Bicis", "Bikes", "Bicis") }
    public var freeDocks: String { pick("Anclajes libres", "Free docks", "Ancoratges lliures") }
    public var noBikesDocked: String { pick("Sin bicis ancladas", "No bikes docked", "Sense bicis ancorades") }
    public var noRating: String { pick("Sin valoración", "No rating", "Sense valoració") }
    public var stand: String { pick("Anclaje", "Stand", "Ancoratge") }
    public var noBuses: String { pick("No vienen autobuses ahora", "No buses coming right now", "No venen autobusos ara") }
    public var noTrains: String { pick("No hay trenes próximos", "No upcoming trains", "No hi ha trens pròxims") }
    public var noUpcomingBuses: String { pick("No hay autobuses próximos", "No upcoming buses", "No hi ha autobusos pròxims") }
    public var noServiceUpdates: String { pick("No hay avisos ahora", "No service updates right now", "No hi ha avisos ara") }
    public var starToSave: String { pick("Marca una parada para guardarla", "Star a stop to save it here", "Marca una parada per a guardar-la") }
    public var busLeftMap: String { pick("El autobús salió del mapa", "The bus left the map", "L'autobús va eixir del mapa") }
    public var stopsNearMe: String { pick("Paradas cerca de mí", "Stops near me", "Parades prop de mi") }
    public var waitingLocation: String { pick("Esperando tu ubicación…", "Waiting for your location…", "Esperant la teua ubicació…") }
    public var serviceUpdates: String { pick("Avisos del servicio", "Service updates", "Avisos del servei") }
    public var chooseStart: String { pick("Elige un origen", "Choose a start", "Tria un origen") }
    public var chooseDestination: String { pick("Elige un destino", "Choose a destination", "Tria una destinació") }
    public var openInMaps: String { pick("Abrir en Mapas", "Open in Maps", "Obrir en Mapes") }
    public var openStopInMaps: String { pick("Abrir parada en Mapas", "Open stop in Maps", "Obrir parada en Mapes") }
    public var openPositionInMaps: String { pick("Abrir posición en Mapas", "Open position in Maps", "Obrir posició en Mapes") }
    public var alertThisLine: String { pick("Avisar de esta línea", "Alert this line", "Avisar d'esta línia") }
    public var alertAtNextStop: String { pick("Avisar en la próxima parada", "Alert at next stop", "Avisar en la pròxima parada") }
    public var stopFollowing: String { pick("Dejar de seguir", "Stop following", "Deixar de seguir") }
    public var copyLine: String { pick("Copiar línea", "Copy line", "Copiar línia") }
    public var arrivalAlerts: String { pick("Avisos de llegada", "Arrival alerts", "Avisos d'arribada") }
    public var arrivalAlertsDesc: String { pick("Avísame cuando una línea marcada esté a estos minutos.", "Notify me when a pinned line is this many minutes away.", "Avisa'm quan una línia marcada estiga a estos minuts.") }
    public var aboutSources: String { pick("Acerca de y fuentes de datos", "About & data sources", "Sobre l'app i fonts de dades") }
    public var languageRestart: String { pick("Cambiar el idioma requiere reiniciar la app.", "Changing the language needs an app restart.", "Canviar l'idioma requereix reiniciar l'app.") }
    public var openNotice: String { pick("Abrir aviso", "Open notice", "Obrir avís") }
}
