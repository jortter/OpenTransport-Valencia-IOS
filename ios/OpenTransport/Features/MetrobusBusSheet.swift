import SwiftUI
import OpenTransportCore

/// A live Metrobús bus of the selected stop: its line, destination,
/// occupancy and how far it is. Its position refreshes about every 20 s.
struct MetrobusBusSheet: View {
    let id: Int

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let vehicle = model.metrobusVehicles.first { $0.id == id }
        let stop = model.map.selectedPlace

        NavigationStack {
            List {
                if let vehicle {
                    Section {
                        HStack(spacing: 12) {
                            LineBadge(line: vehicle.line)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vehicle.destination.isEmpty ? s.lineTitle(String(vehicle.line.dropFirst(2))) : vehicle.destination)
                                    .font(.headline)
                                    .lineLimit(2)
                                if !vehicle.occupancy.isEmpty {
                                    Text(s.occupancy(vehicle.occupancy)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let stop {
                            LabeledContent(stop.name) {
                                Text(TransitMotion.formatDistance(TransitMotion.distanceMeters(
                                    LonLat(lon: stop.lon, lat: stop.lat), LonLat(lon: vehicle.lon, lat: vehicle.lat))))
                                    .monospacedDigit()
                            }
                        }
                    } footer: {
                        Text(s.metrobusPositionNote)
                    }
                    Section {
                        Button {
                            model.map.move(.center(LonLat(lon: vehicle.lon, lat: vehicle.lat), zoom: 15.5))
                        } label: {
                            Label(s.centerOnBus, systemImage: "scope")
                        }
                        Button {
                            openInMaps(lat: vehicle.lat, lon: vehicle.lon, name: s.busTitle(vehicle.id))
                        } label: {
                            Label(s.openPositionInMaps, systemImage: "map")
                        }
                    }
                } else {
                    Text(s.metrobusBusGone).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(s.busTitle(id))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }
}
