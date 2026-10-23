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

    private static let favoritesKey = "favorites"

    init() {
        favorites = (UserDefaults.standard.array(forKey: Self.favoritesKey) as? [Int]) ?? []
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
            transit = data
            client = EmtClient(data: data)
        } catch {
            loadError = String(describing: error)
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
