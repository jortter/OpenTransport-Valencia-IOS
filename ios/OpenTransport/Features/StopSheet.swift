import SwiftUI
import UIKit
import OpenTransportCore

/// Port of `StopSheet` in EmtApp.kt: arrivals for one EMT stop.
struct StopSheet: View {
    let stopId: Int

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var info: StopInfo?
    @State private var loading = true
    @State private var updatesOpen = true

    private var stop: Stop? { model.transit?.stopsById[String(stopId)] }

    var body: some View {
        NavigationStack {
            List {
                if let stop {
                    Section { header(stop) }
                    arrivalsSection(stop)
                    updatesSection(stop)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        model.toggleFavorite(stopId)
                    } label: {
                        Image(systemName: model.isFavorite(stopId) ? "star.fill" : "star")
                    }
                    .accessibilityLabel(model.isFavorite(stopId) ? s.removeFavourite : s.addFavourite)
                    if let stop {
                        ShareLink(item: shareText(stop)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
            .refreshable { await reload() }
        }
        .task(id: stopId) {
            info = nil
            loading = true
            // Android refreshes an open stop every 10 s.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func header(_ stop: Stop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ServiceLogo(network: .emt, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(stop.cleanName)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("\(s.stopCode) \(stop.id)").foregroundStyle(.secondary)
                    if let distance = model.location.distance(to: stop.lat, stop.lon) {
                        Text(TransitMotion.formatDistance(distance)).foregroundStyle(Color.accentColor)
                    }
                }
                .font(.subheadline)
                LineBadges(lines: stop.lines)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func arrivalsSection(_ stop: Stop) -> some View {
        Section(s.arrivals) {
            if loading && info == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let arrivals = info?.arrivals, !arrivals.isEmpty {
                ForEach(Array(arrivals.enumerated()), id: \.offset) { _, arrival in
                    // Tapping an arrival focuses its line, as on Android.
                    Button {
                        model.map.selectLine(arrival.line)
                    } label: {
                        ArrivalRow(arrival: arrival, near: info?.buses.first { $0.line == arrival.line })
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            openInMaps(lat: stop.lat, lon: stop.lon, name: stop.cleanName)
                        } label: {
                            Label(s.openStopInMaps, systemImage: "map")
                        }
                        Button {
                            UIPasteboard.general.string = arrival.line
                        } label: {
                            Label(s.copyLine, systemImage: "doc.on.doc")
                        }
                    }
                }
            } else {
                Text(s.noBuses).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func updatesSection(_ stop: Stop) -> some View {
        let relevant = model.incidents(for: stop.lines)
        if !relevant.isEmpty {
            Section {
                if updatesOpen {
                    ForEach(relevant, id: \.self) { incident in
                        Text(incident.title).font(.subheadline)
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

    private func shareText(_ stop: Stop) -> String {
        "\(stop.cleanName)\nhttps://maps.apple.com/?ll=\(stop.lat),\(stop.lon)"
    }

    private func reload() async {
        guard let client = model.client else { return }
        let result = await client.stop(id: stopId)
        if !Task.isCancelled {
            info = result
            loading = false
        }
    }
}

struct ArrivalRow: View {
    let arrival: Arrival
    var near: NearBus?

    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: arrival.line)
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.destination.isEmpty ? arrival.line : arrival.destination)
                    .lineLimit(1)
                if let near {
                    // Android multiplies this by 1000 and shows km; it is metres already.
                    Text("\(s.busTitle(near.number)) · \(TransitMotion.formatDistance(near.distanceMeters))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(EmtClient.etaLabel(arrival))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
            if arrival.source == "computed" {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
