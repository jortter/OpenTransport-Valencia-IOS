import SwiftUI
import OpenTransportCore

/// Port of `PlaceSheet` in EmtApp.kt: a Metro / Valenbisi / Metrobús /
/// Rodalies point. Network-specific bodies are added per network.
struct PlaceSheet: View {
    let place: Place

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var updatesOpen = true

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                switch place.network {
                case .metro: MetroArrivals(place: place)
                default: EmptyView()
                }
                updatesSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: "\(place.name)\nhttps://maps.apple.com/?ll=\(place.lat),\(place.lon)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ServiceLogo(network: place.network, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(place.name)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !place.detail.isEmpty, place.detail != place.name {
                    Text(place.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let distance = model.location.distance(to: place.lat, place.lon) {
                    Text(TransitMotion.formatDistance(distance)).font(.subheadline).foregroundStyle(Color.accentColor)
                }
                if !place.lines.isEmpty { LineBadges(lines: place.lines) }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var updatesSection: some View {
        let relevant = model.incidents(for: place.lines, network: place.network)
        if !relevant.isEmpty {
            Section {
                if updatesOpen {
                    ForEach(relevant, id: \.self) { incident in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(incident.title).font(.subheadline)
                            if !incident.detail.isEmpty {
                                Text(incident.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label(s.serviceUpdates, systemImage: "exclamationmark.triangle.fill")
                    Spacer()
                    Button(updatesOpen ? s.hide : s.show) { updatesOpen.toggle() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }
}

/// Live Metrovalencia arrivals at a station, refreshed every 30 s.
private struct MetroArrivals: View {
    let place: Place

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var times: [Arrival]?

    var body: some View {
        Section(s.nextDepartures) {
            if let times {
                if times.isEmpty {
                    Text(s.noTrains).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(times.enumerated()), id: \.offset) { _, arrival in
                        HStack(spacing: 12) {
                            // metroapi says "L3"; the bundled badge is "M3".
                            LineBadge(line: "M" + arrival.line.dropFirst(), height: 30)
                            Text(arrival.destination.isEmpty ? "—" : arrival.destination).lineLimit(1)
                            Spacer()
                            Text(arrival.minutes)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .task(id: place.id) {
            guard let station = Int(place.id.dropFirst(3)) else {
                times = []
                return
            }
            while !Task.isCancelled {
                let fresh = await model.metro.arrivals(stationId: station)
                if !Task.isCancelled { times = fresh }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
