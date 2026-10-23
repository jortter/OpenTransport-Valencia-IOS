import OpenTransportCore

/// One-line summary of a place (Android's `placeSubtitle`).
func placeSubtitle(_ place: Place, _ s: Strings) -> String {
    if place.network == .valenbisi {
        return s.bikesSummary(available: max(place.available, 0), free: max(place.free, 0), open: place.open)
    }
    return [place.network.label, place.lines.joined(separator: " · "), place.detail]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}
