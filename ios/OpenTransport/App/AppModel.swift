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
    let map = MapModel()

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
            map.configure(transit: data, client: emt)
            openDemoSelection()
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
