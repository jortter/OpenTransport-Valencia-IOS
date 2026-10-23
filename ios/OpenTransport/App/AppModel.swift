import Foundation
import Observation
import OpenTransportCore

/// App-wide state: static network data, the API client and saved stops.
/// (On Android this all lives inside the `EmtApp()` composable.)
@MainActor
@Observable
final class AppModel {
    private(set) var transit: TransitData?
    private(set) var client: EmtClient?
    private(set) var loadError: String?
    private(set) var favorites: [Int]
    var tab: AppTab
    /// Service alerts of every network, shown in Alerts and in stop/place sheets.
    private(set) var incidents: [Incident]?
    /// Points of the other networks (Metro stations so far).
    private(set) var places: [Place] = []
    /// Bumped on every places reload, so the map knows to redraw them.
    private(set) var placesVersion = 0
    private(set) var metroAssets = MetroAssets(stationNames: [:], lineColors: [:])
    let map = MapModel()
    let location = LocationModel()
    let metro = MetroClient()
    let valenbisi = ValenbisiClient()
    let metrobus = MetrobusClient()
    private(set) var rodalies: RodaliesData?
    /// Route shapes beyond EMT/Metro: Rodalies, and Metrobús lines once loaded.
    private(set) var extraRoutes: [String: BusRoute] = [:]
    private(set) var extraColors: [String: Int] = [:]
    @ObservationIgnored private var metrobusTask: Task<Void, Never>?
    @ObservationIgnored private var bikesTask: Task<Void, Never>?

    private static let favoritesKey = "favorites"

    init() {
        favorites = (UserDefaults.standard.array(forKey: Self.favoritesKey) as? [Int]) ?? []
        // `-initialTab settings` as a launch argument opens that tab (used by CI screenshots).
        tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .map
    }

    /// Switches to the map and opens a stop there (from Saved, search…).
    func openStop(_ id: Int) {
        tab = .map
        map.selectStop(id)
    }

    /// Spanish/Valencian devices start in their language; everything else in English.
    static var defaultLanguage: Language {
        let code = Locale.preferredLanguages.first?.lowercased() ?? ""
        if code.hasPrefix("ca") || code.hasPrefix("va") { return .va }
        if code.hasPrefix("es") { return .es }
        return .en
    }

    func load() async {
        guard transit == nil else { return }
        guard let directory = Bundle.main.url(forResource: "assets", withExtension: nil) else {
            loadError = "Missing bundled assets"
            return
        }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try TransitDataLoader.load(from: directory)
            }.value
            let emt = EmtClient(data: data)
            transit = data
            client = emt
            metroAssets = await Task.detached { MetroAssets.load(from: directory) }.value
            let rodaliesData = await Task.detached { RodaliesData.load(from: directory) }.value
            rodalies = rodaliesData
            extraRoutes.merge(rodaliesData.routes) { _, new in new }
            for line in rodaliesData.routes.keys { extraColors[line] = 0xE30613 }
            replacePlaces(of: .rodalies, with: rodaliesData.places)
            map.configure(transit: data, client: emt)
            location.start()
            openDemoSelection()
            async let metroStations = metro.stations()
            await refreshIncidents()
            replacePlaces(of: .metro, with: await metroStations)
            // Valenbisi availability changes all the time: refresh every minute, like Android.
            bikesTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let stations = await self.valenbisi.stations()
                    self.replacePlaces(of: .valenbisi, with: stations)
                    self.openDemoPlace()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            openDemoPlace()
        } catch {
            loadError = String(describing: error)
        }
    }

    /// `-demoStop 7` / `-demoLine 19` launch arguments (used by CI screenshots).
    private func openDemoSelection() {
        let defaults = UserDefaults.standard
        if let line = defaults.string(forKey: "demoLine") {
            map.selectLine(line)
        } else if defaults.integer(forKey: "demoStop") > 0 {
            map.selectStop(defaults.integer(forKey: "demoStop"))
        }
    }

    /// `-demoPlace mt-20` (used by CI screenshots).
    private func openDemoPlace() {
        guard map.sheet == nil else { return }
        if let id = UserDefaults.standard.string(forKey: "demoPlace"), let place = places.first(where: { $0.id == id }) {
            select(place)
        }
    }

    private func replacePlaces(of network: Network, with fresh: [Place]) {
        guard !fresh.isEmpty else { return }
        places = places.filter { $0.network != network } + fresh
        placesVersion += 1
        // Keep an open place sheet on the fresh numbers (bikes, docks…).
        if let selected = map.selectedPlace, let updated = fresh.first(where: { $0.id == selected.id }) {
            map.refreshSelectedPlace(updated)
        }
    }

    func place(_ id: String) -> Place? { places.first { $0.id == id } }

    /// Every route the map can draw.
    var mapRoutes: [String: BusRoute] {
        (transit?.routes ?? [:]).merging(extraRoutes) { _, extra in extra }
    }

    /// Brand colours for Metro, Rodalies and loaded Metrobús lines.
    var lineColors: [String: Int] {
        metroAssets.lineColors.merging(extraColors) { _, extra in extra }
    }

    /// Opens a place; a Metrobús stop then fetches its lines and their shapes
    /// (Android does the same when one is selected).
    func select(_ place: Place) {
        map.selectPlace(place)
        guard place.network == .metrobus else { return }
        let code = String(place.id.dropFirst(3))
        Task {
            var lines: [String] = []
            for arrival in await metrobus.arrivals(code: code) where arrival.line.hasPrefix("MB") && !lines.contains(arrival.line) {
                lines.append(arrival.line)
            }
            for route in await metrobus.routes(for: lines) {
                extraRoutes[route.line] = BusRoute(ida: RouteDirection(shapes: route.shapes, stops: []),
                                                   vuelta: RouteDirection(shapes: [], stops: []))
                extraColors[route.line] = route.color
            }
            guard map.selectedPlace?.id == place.id else { return }
            var withLines = place
            withLines.lines = lines
            map.refreshSelectedPlace(withLines)
        }
    }

    /// Metrobús has no bulk stop list: load it around the user (or the city
    /// centre) and refresh every 5 minutes, like Android.
    private func startMetrobus() {
        metrobusTask = Task { [weak self] in
            // Give the first location fix a moment before the first load.
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                guard let self else { return }
                let anchor = self.location.location ?? LonLat(lon: -0.3763, lat: 39.4699)
                self.replacePlaces(of: .metrobus, with: await self.metrobus.stops(lat: anchor.lat, lon: anchor.lon))
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
    }

    func refreshIncidents(force: Bool = false) async {
        guard let client else { return }
        async let emt = client.incidents(force: force)
        async let fgv = metro.incidents(locale: fgvLocale, stationNames: metroAssets.stationNames)
        async let metrobusAlerts = metrobus.incidents()
        async let rodaliesAlerts = RodaliesAlerts.fetch()
        incidents = await emt + fgv + metrobusAlerts + rodaliesAlerts
    }

    /// FGV translations are keyed ES / EN / VA (English as fallback).
    private var fgvLocale: String {
        Language.of(UserDefaults.standard.string(forKey: "language") ?? Self.defaultLanguage.rawValue).rawValue
    }

    /// Alerts that mention any of `lines` of `network` (one per line, like the
    /// Android sheets). Metro alerts use bare numbers ("3"), stations "M3".
    func incidents(for lines: [String], network: Network = .emt) -> [Incident] {
        var result: [Incident] = []
        for line in lines {
            let key = network == .metro && line.hasPrefix("M") ? String(line.dropFirst()) : line.uppercased()
            if let match = incidents?.first(where: { $0.network == network && $0.lines.contains(key) }), !result.contains(match) {
                result.append(match)
            }
        }
        return result
    }

    func isFavorite(_ id: Int) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: Int) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            favorites.append(id)
        }
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }
}
