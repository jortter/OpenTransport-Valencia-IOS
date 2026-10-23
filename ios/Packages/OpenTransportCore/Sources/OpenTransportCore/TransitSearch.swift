import Foundation

/// Port of `searchStops` / `searchLines` in EmtApp.kt.
public enum TransitSearch {
    /// Stops whose name has every word of `query`, or whose id contains it
    /// when the query is a number.
    public static func stops(_ stops: [Stop], query: String, includeMetro: Bool = false, limit: Int = 30) -> [Stop] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        let candidates = includeMetro ? stops : stops.filter { !$0.metro }
        if normalized.allSatisfy(\.isNumber) {
            return Array(candidates.filter { String($0.id).contains(normalized) }.prefix(limit))
        }
        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        return Array(candidates.filter { stop in
            let name = stop.name.lowercased()
            return words.allSatisfy { name.contains($0) }
        }.prefix(limit))
    }

    /// Line numbers containing `query`, numeric lines first.
    public static func lines(_ transit: TransitData, query: String, limit: Int = 30) -> [String] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return Array(transit.routes.keys
            .filter { $0.lowercased().contains(normalized) }
            .sorted { a, b in
                let ia = Int(a) ?? Int.max
                let ib = Int(b) ?? Int.max
                return ia != ib ? ia < ib : a < b
            }
            .prefix(limit))
    }
}
