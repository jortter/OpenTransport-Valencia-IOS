import SwiftUI
import OpenTransportCore

/// Port (in progress) of `StopSheet` in EmtApp.kt: arrivals for one EMT stop.
struct StopSheet: View {
    let stopId: Int

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var info: StopInfo?
    @State private var loading = true

    private var stop: Stop? { model.transit?.stopsById[String(stopId)] }

    var body: some View {
        NavigationStack {
            List {
                if let stop {
                    Section {
                        LineBadges(lines: stop.lines)
                    } header: {
                        Text("\(s.stopCode) \(stop.id)")
                    }
                }

                Section(s.arrivals) {
                    if loading && info == nil {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let arrivals = info?.arrivals, !arrivals.isEmpty {
                        ForEach(Array(arrivals.enumerated()), id: \.offset) { _, arrival in
                            ArrivalRow(arrival: arrival)
                        }
                    } else {
                        Text(s.noBuses).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(stop?.cleanName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.toggleFavorite(stopId)
                    } label: {
                        Image(systemName: model.isFavorite(stopId) ? "star.fill" : "star")
                    }
                    .accessibilityLabel(model.isFavorite(stopId) ? s.removeFavourite : s.addFavourite)
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
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(20))
            }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(line: arrival.line)
            Text(arrival.destination)
                .lineLimit(1)
            Spacer()
            Text(EmtClient.etaLabel(arrival))
                .font(.body.weight(.semibold))
                .monospacedDigit()
            if arrival.source == "computed" {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
