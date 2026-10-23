import SwiftUI
import OpenTransportCore

/// Stops, stations and bike docks within a short walk, nearest first
/// (Android's `NearbySheet`).
struct NearbySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    private static let radius = 200.0

    private struct Near: Identifiable {
        let id: String
        let name: String
        let network: Network
        let distance: Double
        let open: () -> Void
    }

    var body: some View {
        NavigationStack {
            Group {
                if let user = model.location.location {
                    let items = nearby(user)
                    if items.isEmpty {
                        ContentUnavailableView(s.noMatches, systemImage: "location.slash")
                    } else {
                        List(items) { item in
                            Button(action: item.open) {
                                HStack(spacing: 12) {
                                    ServiceLogo(network: item.network, size: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).lineLimit(1)
                                        Text(item.network.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(TransitMotion.formatDistance(item.distance))
                                        .foregroundStyle(Color.accentColor)
                                        .monospacedDigit()
                                }
                            }
                            .tint(.primary)
                        }
                    }
                } else {
                    ContentUnavailableView(s.waitingLocation, systemImage: "location")
                }
            }
            .navigationTitle(s.stopsNearMe)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }

    private func nearby(_ user: LonLat) -> [Near] {
        var out: [Near] = []
        for stop in model.transit?.stops ?? [] where !stop.metro {
            let distance = TransitMotion.distanceMeters(user, LonLat(lon: stop.lon, lat: stop.lat))
            if distance <= Self.radius {
                out.append(Near(id: AppModel.stopKey(stop.id), name: stop.cleanName, network: .emt, distance: distance,
                                open: { model.map.selectStop(stop.id) }))
            }
        }
        for place in model.places {
            let distance = TransitMotion.distanceMeters(user, LonLat(lon: place.lon, lat: place.lat))
            if distance <= Self.radius {
                out.append(Near(id: place.id, name: place.name, network: place.network, distance: distance,
                                open: { model.select(place) }))
            }
        }
        return Array(out.sorted { $0.distance < $1.distance }.prefix(30))
    }
}
