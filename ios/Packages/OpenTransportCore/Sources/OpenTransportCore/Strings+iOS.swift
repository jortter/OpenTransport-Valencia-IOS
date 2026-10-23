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

    public var aboutUnofficial: String {
        pick("App no oficial. Sin relación con EMT València, Metrovalencia / FGV, ATMV / Met GO, Valenbisi / JCDecaux, el Ajuntament de València ni ningún otro operador. Las marcas y logotipos pertenecen a sus propietarios.",
             "Unofficial app. Not affiliated with, endorsed by, or connected to EMT València, Metrovalencia / FGV, ATMV / Met GO, Valenbisi / JCDecaux, the Ajuntament de València or any other operator or company. All trademarks and logos belong to their respective owners.",
             "App no oficial. Sense relació amb EMT València, Metrovalencia / FGV, ATMV / Met GO, Valenbisi / JCDecaux, l'Ajuntament de València ni cap altre operador. Les marques i logotips pertanyen als seus propietaris.")
    }

    public var aboutData: String {
        pick("Datos en directo y mapas de fuentes públicas y herramientas de la comunidad: EMT València, Metrovalencia (metrovalencia.es, metroapi.alexbadi.es), Valenbisi (JCDecaux), Renfe, datos abiertos de València (CC BY 4.0), colaboradores de OpenStreetMap (ODbL), CARTO y MapLibre. FOSSGIS proporciona las rutas a pie.",
             "Live data and maps come from public/open sources and community tools, including EMT València, Metrovalencia (metrovalencia.es, metroapi.alexbadi.es), Valenbisi via JCDecaux, Renfe, València open data (CC BY 4.0), OpenStreetMap contributors (ODbL), CARTO basemaps and MapLibre. FOSSGIS provides the walking routes.",
             "Dades en directe i mapes de fonts públiques i eines de la comunitat: EMT València, Metrovalencia (metrovalencia.es, metroapi.alexbadi.es), Valenbisi (JCDecaux), Renfe, dades obertes de València (CC BY 4.0), col·laboradors d'OpenStreetMap (ODbL), CARTO i MapLibre. FOSSGIS proporciona les rutes a peu.")
    }

    public var aboutWarranty: String {
        pick("Se ofrece «tal cual», sin garantía; los tiempos y posiciones pueden llegar con retraso o ser inexactos. Usa la información oficial de los operadores para decidir tus viajes.",
             "Provided “as is”, without warranty; times and positions may be delayed or inaccurate. Use the official operators' information for travel decisions.",
             "S'ofereix «tal qual», sense garantia; els temps i posicions poden arribar amb retard o ser inexactes. Usa la informació oficial dels operadors per a decidir els teus viatges.")
    }

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
